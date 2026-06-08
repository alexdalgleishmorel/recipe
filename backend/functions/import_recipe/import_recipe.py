"""AI recipe-import handler (#19) — copies the recipes/me/uploads Lambda dispatch pattern.

Parses an uploaded recipe photo or PDF into a structured ``Recipe`` draft by calling the **Anthropic
API directly** (the official ``anthropic`` Python SDK, model ``claude-opus-4-8``) — NOT Bedrock:

    POST /recipes/import -> { ...Recipe draft (no id) }

The caller sends the file inline as ``{contentBase64, contentType, filename}`` (``image/*`` or
``application/pdf``); it may instead send ``{key}`` to fetch the bytes from the uploads S3 bucket
(the same private bucket #17's presign writes to — the exec role already has ``s3:GetObject``). The
handler builds a single ``messages.create`` request with the file as an ``image``/``document`` block
plus a text instruction, constrains the response with **structured outputs**
(``output_config.format`` carrying :data:`RECIPE_JSON_SCHEMA`, which mirrors the Dart ``Recipe``
fields), and returns the parsed JSON draft. It does NOT persist — the frontend reviews the draft and
then saves it via ``POST /recipes``.

Entitlement gate: the caller's profile is loaded via the users DAL (keyed by ``common.get_user_id``)
and the request is rejected with **403** unless ``canAiImport`` is true. The owner grants that flag
once via the admin handler (#20).

The Anthropic API key lives in **AWS Secrets Manager** (secret name :data:`ANTHROPIC_SECRET_NAME`);
it is read at runtime via boto3 and cached at module load so it is never in the client or the repo.
The exec role is granted ``secretsmanager:GetSecretValue`` on that secret in ``infra/shared/import.tf``.
"""

from __future__ import annotations

import base64
import binascii
import json
import os
from typing import Any, Optional

import boto3

from common import api, get_user_id
from data_access import users

# --- configuration --------------------------------------------------------------------------------

# Anthropic model used for parsing. Structured outputs are supported on claude-opus-4-8.
MODEL = "claude-opus-4-8"

# Secrets Manager secret holding the Anthropic API key (read by name; see infra/shared/import.tf).
ANTHROPIC_SECRET_NAME = "recipe/anthropic-api-key"

# Env var carrying the private uploads bucket name (shared with #17's uploads handler), used only for
# the optional ``{key}`` path that fetches bytes from S3 instead of accepting them inline.
BUCKET_ENV = "UPLOADS_BUCKET"

# Cap the model's output so a runaway response can't hang the Lambda; a recipe draft is small.
MAX_TOKENS = 4096

# Accepted inline content types: any image/* plus PDF. Anything else is a 400.
PDF_CONTENT_TYPE = "application/pdf"

# JSON schema for the structured output — mirrors the Dart Recipe fields (frontend/lib/models/
# recipe.dart). ``id`` and ``image`` are intentionally omitted: the server assigns the id on save
# (POST /recipes) and the image is the uploaded photo, not something the model invents.
RECIPE_JSON_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "cuisine": {"type": "string"},
        "description": {"type": "string"},
        "prepTime": {"type": "integer"},
        "cookTime": {"type": "integer"},
        "servings": {"type": "integer"},
        "tags": {"type": "array", "items": {"type": "string"}},
        "dietary": {"type": "array", "items": {"type": "string"}},
        "author": {"type": "string"},
        "ingredients": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "amount": {"type": "string"},
                    "unit": {"type": "string"},
                    "name": {"type": "string"},
                },
                "required": ["amount", "unit", "name"],
                "additionalProperties": False,
            },
        },
        "instructions": {"type": "array", "items": {"type": "string"}},
    },
    "required": [
        "title",
        "cuisine",
        "description",
        "prepTime",
        "cookTime",
        "servings",
        "tags",
        "dietary",
        "author",
        "ingredients",
        "instructions",
    ],
    "additionalProperties": False,
}

# Instruction paired with the file. Times are minutes; missing fields are filled with sensible empties.
EXTRACT_PROMPT = (
    "Extract the recipe from the attached file into the required JSON schema. "
    "Use whole minutes for prepTime and cookTime and an integer servings count. "
    "Split each ingredient into amount, unit, and name (leave amount/unit empty when not stated). "
    "Each instruction is one step. Infer cuisine and dietary tags when obvious; otherwise leave them "
    "empty. If a field is not present in the recipe, use an empty string, 0, or an empty list."
)

# Module-level caches, built lazily so importing the module needs no AWS creds/region/network.
_secrets_client = None
_s3_client = None
_anthropic_client = None


def _secrets() -> Any:
    """Return the boto3 Secrets Manager client, built lazily."""
    global _secrets_client
    if _secrets_client is None:
        _secrets_client = boto3.client("secretsmanager")
    return _secrets_client


def _s3() -> Any:
    """Return the boto3 S3 client, built lazily (only used by the optional ``{key}`` path)."""
    global _s3_client
    if _s3_client is None:
        _s3_client = boto3.client("s3")
    return _s3_client


def _api_key() -> str:
    """Read the Anthropic API key from Secrets Manager by name (raises a 500 on failure)."""
    try:
        secret = _secrets().get_secret_value(SecretId=ANTHROPIC_SECRET_NAME)
    except Exception as exc:  # noqa: BLE001 - surfaced as a 500; details go to CloudWatch
        raise api.ApiError(500, "could not read the Anthropic API key") from exc
    value = secret.get("SecretString")
    if not value:
        raise api.ApiError(500, "Anthropic API key secret is empty")
    # The secret may be a bare key or a JSON blob like {"apiKey": "..."}; accept either.
    value = value.strip()
    if value.startswith("{"):
        try:
            parsed = json.loads(value)
        except ValueError:
            parsed = {}
        for field in ("apiKey", "api_key", "ANTHROPIC_API_KEY", "key"):
            if parsed.get(field):
                return str(parsed[field])
        raise api.ApiError(500, "Anthropic API key secret has no recognized key field")
    return value


def _client() -> Any:
    """Return the Anthropic SDK client, built lazily and cached (key read once from Secrets Manager).

    Imported inside the function so the module imports without the ``anthropic`` package present (the
    tests monkeypatch this function to avoid any real client/network).
    """
    global _anthropic_client
    if _anthropic_client is None:
        import anthropic  # local import: keeps module import cheap and test-friendly

        _anthropic_client = anthropic.Anthropic(api_key=_api_key())
    return _anthropic_client


def _bucket() -> str:
    """Return the configured uploads bucket name; raise a 500-mapping error if unset."""
    bucket = os.environ.get(BUCKET_ENV)
    if not bucket:
        raise api.ApiError(500, f"{BUCKET_ENV} is not configured")
    return bucket


def _file_block(content_type: str, data_b64: str) -> dict:
    """Build the Anthropic content block for the file (image or PDF) from base64 bytes."""
    ct = content_type.lower().strip()
    if ct == PDF_CONTENT_TYPE:
        return {
            "type": "document",
            "source": {"type": "base64", "media_type": PDF_CONTENT_TYPE, "data": data_b64},
        }
    if ct.startswith("image/"):
        return {
            "type": "image",
            "source": {"type": "base64", "media_type": ct, "data": data_b64},
        }
    raise api.ApiError(400, f"unsupported contentType '{content_type}' (expected image/* or PDF)")


def _resolve_file(body: dict) -> tuple[str, str]:
    """Resolve ``(contentType, base64Data)`` from the request body.

    Primary path: inline ``{contentBase64, contentType}``. Optional path: ``{key}`` (+ optional
    ``contentType``) fetches the object from the uploads bucket and infers the content type from S3.
    """
    key = body.get("key")
    if key:
        if not isinstance(key, str):
            raise api.ApiError(400, "key must be a string")
        try:
            obj = _s3().get_object(Bucket=_bucket(), Key=key)
        except Exception as exc:  # noqa: BLE001 - missing/forbidden object -> 400
            raise api.ApiError(400, f"could not read object '{key}'") from exc
        raw = obj["Body"].read()
        content_type = body.get("contentType") or obj.get("ContentType") or ""
        if not isinstance(content_type, str) or not content_type:
            raise api.ApiError(400, "could not determine contentType for the object")
        return content_type, base64.b64encode(raw).decode("ascii")

    content_b64 = body.get("contentBase64")
    content_type = body.get("contentType")
    if not content_b64 or not isinstance(content_b64, str):
        raise api.ApiError(400, "contentBase64 is required (or provide a key)")
    if not content_type or not isinstance(content_type, str):
        raise api.ApiError(400, "contentType is required")
    # Validate the base64 up front so a bad payload is a clean 400, not an Anthropic-side error.
    try:
        base64.b64decode(content_b64, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise api.ApiError(400, "contentBase64 is not valid base64") from exc
    return content_type, content_b64


def _parse_recipe(content_type: str, data_b64: str) -> dict:
    """Call Anthropic with the file + structured-output schema and return the parsed Recipe draft."""
    response = _client().messages.create(
        model=MODEL,
        max_tokens=MAX_TOKENS,
        output_config={"format": {"type": "json_schema", "schema": RECIPE_JSON_SCHEMA}},
        messages=[
            {
                "role": "user",
                "content": [
                    _file_block(content_type, data_b64),
                    {"type": "text", "text": EXTRACT_PROMPT},
                ],
            }
        ],
    )
    # output_config.format guarantees the first text block is valid JSON matching the schema.
    text = next((b.text for b in response.content if getattr(b, "type", None) == "text"), None)
    if not text:
        raise api.ApiError(502, "the model returned no recipe draft")
    try:
        return json.loads(text)
    except (ValueError, TypeError) as exc:
        raise api.ApiError(502, "the model returned an unparseable recipe draft") from exc


def _import(user_id: str, event: dict) -> dict:
    """Gate on ``canAiImport``, parse the uploaded file, and return the Recipe draft (no persist)."""
    profile = users.get(user_id, user_id)
    if not profile or not profile.get("canAiImport"):
        return api.error(403, "AI import is not enabled for this account")

    body = api.body(event)
    content_type, data_b64 = _resolve_file(body)
    draft = _parse_recipe(content_type, data_b64)
    return api.ok(draft)


@api.route
def handler(event: dict[str, Any], context: Any) -> dict:
    """API Gateway v2 (payload format 2.0) proxy entrypoint; dispatches POST /recipes/import."""
    user_id = get_user_id(event)
    method = (event.get("requestContext", {}).get("http", {}) or {}).get("method", "").upper()

    if method == "POST":
        return _import(user_id, event)

    return api.error(405, f"method {method or '?'} not allowed on this route")
