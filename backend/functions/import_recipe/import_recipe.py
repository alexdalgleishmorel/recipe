"""Cost-optimized AI recipe-import handler (#76) — tiered JSON/Haiku/Sonnet pipeline + multi-file.

Parses uploaded recipe files into structured ``Recipe`` drafts while minimizing $/successfully-parsed
recipe behind a hard reliability floor. ``POST /recipes/import`` (auth=true) accepts either:

* **Single (back-compat):** ``{contentBase64, contentType, filename}`` OR ``{key, contentType?}``
  -> ``200`` with a single Recipe draft object (the historical shape).
* **Multi:** ``{files:[{contentBase64, contentType, filename}, ...], mode?:"sync"|"batch"}``
  -> ``200 {"results":[{"filename","ok",("tier","draft")|("error")}], "mode":"sync"}`` (sync), or
  ``{"mode":"batch","batchId":str}`` (batch). A retrieve route ``GET /recipes/import/batch/{id}``
  returns the batch status/results.

Per-file routing (cheapest-first), `(contentType, bytes, filename)` -> result:

* ``application/json`` / ``.json`` -> strictly validate against :data:`RECIPE_JSON_SCHEMA` with
  ``jsonschema`` plus the completeness gate. Pass -> draft, tier ``"json"``, **no AI call**. Cost $0.
* ``image/*`` -> downsize with Pillow (longest edge <= 1568) -> AI tier.
* ``application/pdf`` -> render pages with PyMuPDF (fitz) at a DPI capped so longest edge <= 1568 and
  send as ``image`` blocks (``PDF_MODE=image``, default), avoiding the document text-token surcharge;
  ``PDF_MODE=document`` sends the raw PDF as a ``document`` block instead.

AI tier reliability gate + fallback: call :data:`PRIMARY_MODEL` (structured output + cached system
block) -> completeness check -> on failure retry once on :data:`FALLBACK_MODEL` -> still failing ->
that file's result is ``ok:false`` with a clear error (never emit incomplete drafts).

The Anthropic API key lives in **AWS Secrets Manager** (secret :data:`ANTHROPIC_SECRET_NAME`); it is
read at runtime via boto3 and cached. The lazy :func:`_client` seam lets tests stub the SDK with no
network. Cost instrumentation logs one structured JSON line per AI call (``event=recipe_import``).
"""

from __future__ import annotations

import base64
import binascii
import concurrent.futures
import io
import json
import logging
import os
from typing import Any, Optional

import boto3

from common import api, get_user_id
from data_access import users

logger = logging.getLogger(__name__)
if not logger.handlers:
    logger.setLevel(logging.INFO)

# --- configuration --------------------------------------------------------------------------------

# Models are env-overridable so the tier can be tuned without a code change. Defaults are the
# cheapest reliable pair; NEVER Opus. Structured outputs are supported on both.
PRIMARY_MODEL = os.environ.get("PRIMARY_MODEL", "claude-haiku-4-5")
FALLBACK_MODEL = os.environ.get("FALLBACK_MODEL", "claude-sonnet-4-6")

# Secrets Manager secret holding the Anthropic API key (read by name; see infra/shared/import.tf).
ANTHROPIC_SECRET_NAME = "recipe/anthropic-api-key"

# Env var carrying the private uploads bucket name (shared with #17's uploads handler), used only for
# the optional ``{key}`` path that fetches bytes from S3 instead of accepting them inline.
BUCKET_ENV = "UPLOADS_BUCKET"

# Cap the model's output so a runaway response can't hang the Lambda; a recipe draft is small.
MAX_TOKENS = 4096

# Anthropic's hard limit on an image's longest edge; we downsize/render to fit it (cost + acceptance).
MAX_IMAGE_EDGE = 1568

PDF_CONTENT_TYPE = "application/pdf"
JSON_CONTENT_TYPE = "application/json"

# How PDFs are sent to the model: "image" (default) renders pages to images (no text surcharge);
# "document" sends the raw PDF as a document block (bills image+text per page).
PDF_MODE = os.environ.get("PDF_MODE", "image").lower()

# Max files accepted per multi-file request; extras get a per-file error (not a 400 of the request).
MAX_FILES = int(os.environ.get("MAX_FILES", "10"))

# Per-MTok prices (USD) used to attribute spend per file. Batch billing is half (applied at call site).
HAIKU_INPUT_PER_MTOK = float(os.environ.get("HAIKU_INPUT_PER_MTOK", "1"))
HAIKU_OUTPUT_PER_MTOK = float(os.environ.get("HAIKU_OUTPUT_PER_MTOK", "5"))
SONNET_INPUT_PER_MTOK = float(os.environ.get("SONNET_INPUT_PER_MTOK", "3"))
SONNET_OUTPUT_PER_MTOK = float(os.environ.get("SONNET_OUTPUT_PER_MTOK", "15"))

# JSON schema for the structured output — mirrors the Dart Recipe fields (frontend/lib/models/
# recipe.dart). ``id`` and ``image`` are intentionally omitted: the server assigns the id on save
# (POST /recipes) and the image is the uploaded photo, not something the model invents. This is the
# canonical schema, reused by the JSON-upload validator, the AI structured output, and the UI
# (docs/recipe-import-schema.md).
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

# Substantial static system prompt: detailed field guidance + ONE short few-shot. Kept long on purpose
# so it exceeds Haiku 4.5's 4096-token prompt-cache minimum (so cache_control engages) AND lifts the
# smaller model's success rate. This block is identical on every call -> a cache hit after the first.
SYSTEM_PROMPT = (
    "You are a meticulous recipe-extraction engine. You read a recipe from an attached image or "
    "PDF page and return EXACTLY the JSON object described by the response schema — nothing else.\n"
    "\n"
    "Field-by-field guidance:\n"
    "- title: the dish name as written. If the page has no explicit title, infer a concise name "
    "from the dish; never leave it empty when any recipe is present.\n"
    "- cuisine: the cuisine/region (e.g. 'Italian', 'Thai', 'Mexican'). Infer from ingredients and "
    "technique when not stated; use an empty string only if genuinely unclear.\n"
    "- description: one or two plain sentences summarizing the dish. Empty string if none can be "
    "reasonably inferred.\n"
    "- prepTime / cookTime: whole minutes as integers. Convert hours to minutes (1h30m -> 90). Use "
    "0 when not stated. Never invent large values.\n"
    "- servings: integer number of servings/yield. Use 0 when not stated.\n"
    "- tags: short lowercase keywords (e.g. 'soup', 'weeknight', 'dessert'). Empty list if none.\n"
    "- dietary: dietary labels that clearly apply (e.g. 'vegetarian', 'vegan', 'gluten-free'). Only "
    "include a label when the ingredients support it. Empty list if none.\n"
    "- author: the recipe's author/source if shown; empty string otherwise.\n"
    "- ingredients: an array of objects, each split into amount, unit, and name. amount is the "
    "numeric quantity as a string ('2', '1/2', '1.5'); unit is the measurement word ('cup', 'tbsp', "
    "'g', 'clove') or empty when none; name is the ingredient itself with no quantity. Leave amount "
    "and/or unit as empty strings when the recipe does not state them. Preserve ingredient order.\n"
    "- instructions: an array of strings, ONE step per element, in order, lightly cleaned. Do not "
    "merge multiple steps into one element and do not number them.\n"
    "\n"
    "Rules: Extract only what the recipe supports; do not hallucinate ingredients or steps. If the "
    "image clearly contains no recipe, still return the schema with empty/zero values. Output must "
    "validate against the provided JSON schema.\n"
    "\n"
    "Example (illustrative shape only):\n"
    "{\n"
    '  "title": "Garlic Butter Pasta",\n'
    '  "cuisine": "Italian",\n'
    '  "description": "A fast weeknight pasta in a garlicky butter sauce.",\n'
    '  "prepTime": 5,\n'
    '  "cookTime": 15,\n'
    '  "servings": 2,\n'
    '  "tags": ["pasta", "weeknight"],\n'
    '  "dietary": ["vegetarian"],\n'
    '  "author": "",\n'
    '  "ingredients": [\n'
    '    {"amount": "8", "unit": "oz", "name": "spaghetti"},\n'
    '    {"amount": "3", "unit": "tbsp", "name": "butter"},\n'
    '    {"amount": "3", "unit": "clove", "name": "garlic, minced"},\n'
    '    {"amount": "", "unit": "", "name": "salt"}\n'
    "  ],\n"
    '  "instructions": [\n'
    '    "Boil the spaghetti in salted water until al dente.",\n'
    '    "Melt the butter and gently cook the garlic until fragrant.",\n'
    '    "Toss the drained pasta in the garlic butter and season with salt."\n'
    "  ]\n"
    "}"
)

# Short per-request instruction paired with the file (the bulky guidance lives in SYSTEM_PROMPT).
EXTRACT_PROMPT = (
    "Extract the recipe from the attached file into the required JSON schema, following the system "
    "guidance for each field."
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


# --- completeness gate (shared by the JSON tier and the AI tier) ----------------------------------


def is_complete(draft: Any) -> bool:
    """Return True iff ``draft`` is a usable Recipe: non-empty title, >=1 named ingredient, >=1 step.

    This is the reliability floor: a draft missing any of these is rejected rather than emitted.
    """
    if not isinstance(draft, dict):
        return False
    title = draft.get("title")
    if not isinstance(title, str) or not title.strip():
        return False
    ingredients = draft.get("ingredients")
    if not isinstance(ingredients, list) or not any(
        isinstance(i, dict) and isinstance(i.get("name"), str) and i["name"].strip()
        for i in ingredients
    ):
        return False
    instructions = draft.get("instructions")
    if not isinstance(instructions, list) or not any(
        isinstance(s, str) and s.strip() for s in instructions
    ):
        return False
    return True


def _validate_json_upload(raw: bytes) -> dict:
    """Strictly validate a JSON upload against the canonical schema + completeness gate.

    Returns the parsed draft on success; raises :class:`ValueError` with a specific message on any
    schema or completeness failure (the caller turns it into an ``ok:false`` per-file error).
    """
    import jsonschema  # local import keeps module import cheap; vendored into the bundle

    try:
        draft = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as exc:
        raise ValueError(f"not valid JSON: {exc}") from exc
    try:
        jsonschema.validate(draft, RECIPE_JSON_SCHEMA)
    except jsonschema.ValidationError as exc:
        raise ValueError(f"off-schema: {exc.message}") from exc
    if not is_complete(draft):
        raise ValueError(
            "off-schema: incomplete recipe (needs a title, at least one named ingredient, and at "
            "least one instruction)"
        )
    return draft


# --- file preparation (image downsize / PDF render) -----------------------------------------------


def _downsize_image(data: bytes) -> tuple[str, str]:
    """Downsize an image so its longest edge <= MAX_IMAGE_EDGE; return (media_type, base64).

    Re-encodes to PNG (lossless, broadly accepted) after fitting. Cheaper for the model (fewer image
    tokens) and guarantees Anthropic's edge limit is satisfied.
    """
    from PIL import Image  # local import; Pillow is vendored into the bundle

    with Image.open(io.BytesIO(data)) as img:
        img = img.convert("RGB")
        longest = max(img.size)
        if longest > MAX_IMAGE_EDGE:
            scale = MAX_IMAGE_EDGE / float(longest)
            new_size = (max(1, int(img.width * scale)), max(1, int(img.height * scale)))
            img = img.resize(new_size, Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
    return "image/png", base64.b64encode(buf.getvalue()).decode("ascii")


def _render_pdf_pages(data: bytes) -> list[str]:
    """Render PDF pages to base64 PNGs at a DPI capped so each page's longest edge <= MAX_IMAGE_EDGE.

    Image-only path (PDF_MODE=image): avoids the per-page text-token surcharge of document blocks.
    """
    import fitz  # PyMuPDF; local import, vendored into the bundle

    images: list[str] = []
    with fitz.open(stream=data, filetype="pdf") as doc:
        for page in doc:
            rect = page.rect
            longest_pts = max(rect.width, rect.height) or 1.0
            # Points are 1/72 inch; choose a DPI so longest_pts * dpi/72 <= MAX_IMAGE_EDGE.
            dpi = min(150, int(MAX_IMAGE_EDGE * 72.0 / longest_pts))
            dpi = max(36, dpi)
            pix = page.get_pixmap(dpi=dpi)
            images.append(base64.b64encode(pix.tobytes("png")).decode("ascii"))
    return images


def _content_blocks(content_type: str, data: bytes) -> list[dict]:
    """Build the Anthropic content block(s) for a prepared file (image, rendered/raw PDF)."""
    ct = (content_type or "").lower().strip()
    if ct == PDF_CONTENT_TYPE:
        if PDF_MODE == "document":
            return [
                {
                    "type": "document",
                    "source": {
                        "type": "base64",
                        "media_type": PDF_CONTENT_TYPE,
                        "data": base64.b64encode(data).decode("ascii"),
                    },
                }
            ]
        blocks = []
        for page_b64 in _render_pdf_pages(data):
            blocks.append(
                {
                    "type": "image",
                    "source": {"type": "base64", "media_type": "image/png", "data": page_b64},
                }
            )
        return blocks
    if ct.startswith("image/"):
        media_type, b64 = _downsize_image(data)
        return [{"type": "image", "source": {"type": "base64", "media_type": media_type, "data": b64}}]
    raise ValueError(f"unsupported contentType '{content_type}'")


def _message_request(blocks: list[dict], model: str) -> dict:
    """Build the kwargs for a ``messages.create`` / batch request for one file."""
    return {
        "model": model,
        "max_tokens": MAX_TOKENS,
        "output_config": {"format": {"type": "json_schema", "schema": RECIPE_JSON_SCHEMA}},
        "system": [{"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}],
        "messages": [
            {
                "role": "user",
                "content": [*blocks, {"type": "text", "text": EXTRACT_PROMPT}],
            }
        ],
    }


# --- cost instrumentation -------------------------------------------------------------------------


def _rates(model: str) -> tuple[float, float]:
    """Return (input_per_mtok, output_per_mtok) for ``model`` (Sonnet rates if it isn't Haiku)."""
    if "haiku" in model:
        return HAIKU_INPUT_PER_MTOK, HAIKU_OUTPUT_PER_MTOK
    return SONNET_INPUT_PER_MTOK, SONNET_OUTPUT_PER_MTOK


def _cost_usd(model: str, input_tokens: int, output_tokens: int, *, batch: bool = False) -> float:
    """Compute USD cost from token counts and per-MTok env rates (batch billing is half)."""
    in_rate, out_rate = _rates(model)
    cost = (input_tokens * in_rate + output_tokens * out_rate) / 1_000_000.0
    if batch:
        cost *= 0.5
    return round(cost, 8)


def _usage_fields(usage: Any) -> dict:
    """Extract token counts from a response.usage object (dict or attr-style), defaulting to 0."""

    def _get(name: str) -> int:
        if usage is None:
            return 0
        if isinstance(usage, dict):
            val = usage.get(name)
        else:
            val = getattr(usage, name, None)
        return int(val) if isinstance(val, (int, float)) else 0

    return {
        "input_tokens": _get("input_tokens"),
        "output_tokens": _get("output_tokens"),
        "cache_read_input_tokens": _get("cache_read_input_tokens"),
        "cache_creation_input_tokens": _get("cache_creation_input_tokens"),
    }


def _log_import(
    *, filename: str, tier: str, mode: str, model: Optional[str], usage: Any, cost_usd: float
) -> None:
    """Emit one structured JSON log line per file for cost/usage analytics."""
    fields = _usage_fields(usage) if usage is not None else {
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_read_input_tokens": 0,
        "cache_creation_input_tokens": 0,
    }
    record = {
        "event": "recipe_import",
        "filename": filename,
        "tier": tier,
        "mode": mode,
        "model": model,
        "cost_usd": cost_usd,
        **fields,
    }
    logger.info(json.dumps(record))


def estimate_input_tokens(content_type: str, data: bytes, *, model: Optional[str] = None) -> int:
    """Estimate the input-token count for one file via the Anthropic ``count_tokens`` API.

    Builds the same request shape the AI tier sends and asks the SDK to count it. Useful for
    pre-flight cost estimates; exercised in the tests against the stubbed client.
    """
    blocks = _content_blocks(content_type, data)
    req = _message_request(blocks, model or PRIMARY_MODEL)
    resp = _client().messages.count_tokens(
        model=req["model"],
        system=req["system"],
        messages=req["messages"],
    )
    if isinstance(resp, dict):
        return int(resp.get("input_tokens", 0))
    return int(getattr(resp, "input_tokens", 0))


# --- AI tier (primary -> fallback) ----------------------------------------------------------------


def _draft_from_response(response: Any) -> Optional[dict]:
    """Pull the JSON draft out of an Anthropic response, or None if it can't be parsed."""
    text = next(
        (b.text for b in getattr(response, "content", []) if getattr(b, "type", None) == "text"),
        None,
    )
    if not text:
        return None
    try:
        parsed = json.loads(text)
    except (ValueError, TypeError):
        return None
    return parsed if isinstance(parsed, dict) else None


def _call_model(blocks: list[dict], model: str, filename: str) -> Optional[dict]:
    """Call one model, log cost, and return a complete draft or None (incomplete/unparseable)."""
    req = _message_request(blocks, model)
    response = _client().messages.create(**req)
    draft = _draft_from_response(response)
    usage = getattr(response, "usage", None)
    fields = _usage_fields(usage)
    cost = _cost_usd(model, fields["input_tokens"], fields["output_tokens"])
    tier = "haiku" if "haiku" in model else "sonnet"
    _log_import(filename=filename, tier=tier, mode="sync", model=model, usage=usage, cost_usd=cost)
    return draft if draft is not None and is_complete(draft) else None


def _parse_with_ai(content_type: str, data: bytes, filename: str) -> tuple[dict, str]:
    """Run the AI tier: PRIMARY_MODEL, then one FALLBACK_MODEL retry. Returns (draft, tier).

    Raises :class:`ValueError` if both models fail the completeness gate (never emits an incomplete
    draft) or if the file can't be prepared.
    """
    blocks = _content_blocks(content_type, data)  # may raise ValueError (unsupported / render error)

    draft = _call_model(blocks, PRIMARY_MODEL, filename)
    if draft is not None:
        return draft, "haiku" if "haiku" in PRIMARY_MODEL else "sonnet"

    draft = _call_model(blocks, FALLBACK_MODEL, filename)
    if draft is not None:
        return draft, "sonnet" if "sonnet" in FALLBACK_MODEL else "haiku"

    raise ValueError("the model could not extract a complete recipe from this file")


# --- per-file routing -----------------------------------------------------------------------------


def _is_json_file(content_type: str, filename: str) -> bool:
    ct = (content_type or "").lower().strip()
    return ct == JSON_CONTENT_TYPE or (filename or "").lower().endswith(".json")


def _process_file(content_type: str, data: bytes, filename: str) -> dict:
    """Route one file to its tier and return its draft + tier. Raises ValueError on a per-file error."""
    if _is_json_file(content_type, filename):
        draft = _validate_json_upload(data)  # raises ValueError on schema/completeness failure
        _log_import(filename=filename, tier="json", mode="sync", model=None, usage=None, cost_usd=0.0)
        return {"draft": draft, "tier": "json"}

    ct = (content_type or "").lower().strip()
    if ct == PDF_CONTENT_TYPE or ct.startswith("image/"):
        draft, tier = _parse_with_ai(content_type, data, filename)
        return {"draft": draft, "tier": tier}

    raise ValueError(f"unsupported contentType '{content_type}'")


def _process_file_result(spec: dict) -> dict:
    """Wrap :func:`_process_file` for a multi-file entry: never raises, returns a result dict."""
    filename = spec.get("filename") or ""
    try:
        content_type, data = _decode_file_spec(spec)
        out = _process_file(content_type, data, filename)
        return {"filename": filename, "ok": True, "tier": out["tier"], "draft": out["draft"]}
    except Exception as exc:  # noqa: BLE001 - one file's failure must not sink the batch
        return {"filename": filename, "ok": False, "error": str(exc)}


# --- request decoding -----------------------------------------------------------------------------


def _decode_b64(content_b64: Any) -> bytes:
    """Decode a base64 string to bytes, raising ValueError on a bad payload."""
    if not content_b64 or not isinstance(content_b64, str):
        raise ValueError("contentBase64 is required")
    try:
        return base64.b64decode(content_b64, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("contentBase64 is not valid base64") from exc


def _decode_file_spec(spec: dict) -> tuple[str, bytes]:
    """Resolve (contentType, bytes) for a single file spec (inline contentBase64, or S3 key)."""
    if not isinstance(spec, dict):
        raise ValueError("each file must be an object")
    key = spec.get("key")
    if key:
        if not isinstance(key, str):
            raise ValueError("key must be a string")
        try:
            obj = _s3().get_object(Bucket=_bucket(), Key=key)
        except Exception as exc:  # noqa: BLE001 - missing/forbidden object -> per-file error
            raise ValueError(f"could not read object '{key}'") from exc
        raw = obj["Body"].read()
        content_type = spec.get("contentType") or obj.get("ContentType") or ""
        if not isinstance(content_type, str) or not content_type:
            raise ValueError("could not determine contentType for the object")
        return content_type, raw
    content_type = spec.get("contentType")
    if not content_type or not isinstance(content_type, str):
        raise ValueError("contentType is required")
    return content_type, _decode_b64(spec.get("contentBase64"))


# --- batch mode -----------------------------------------------------------------------------------


def _submit_batch(specs: list[dict]) -> str:
    """Submit all files' requests to the Message Batches API (50% off) and return the batch id."""
    requests = []
    for idx, spec in enumerate(specs):
        content_type, data = _decode_file_spec(spec)  # raises ValueError -> 400 at the call site
        blocks = _content_blocks(content_type, data)
        requests.append({"custom_id": f"file-{idx}", "params": _message_request(blocks, PRIMARY_MODEL)})
    batch = _client().messages.batches.create(requests=requests)
    batch_id = batch.get("id") if isinstance(batch, dict) else getattr(batch, "id", None)
    if not batch_id:
        raise api.ApiError(502, "the batch API returned no id")
    return batch_id


def _retrieve_batch(batch_id: str) -> dict:
    """Return the status/results of a previously submitted batch (best-effort passthrough)."""
    batch = _client().messages.batches.retrieve(batch_id)
    status = batch.get("processing_status") if isinstance(batch, dict) else getattr(
        batch, "processing_status", None
    )
    out: dict[str, Any] = {"batchId": batch_id, "status": status}
    if status == "ended":
        results = []
        for entry in _client().messages.batches.results(batch_id):
            results.append(entry if isinstance(entry, dict) else getattr(entry, "__dict__", {}))
        out["results"] = results
    return out


# --- request handling -----------------------------------------------------------------------------


def _import_single(body: dict) -> dict:
    """Back-compat single-file path: returns the bare Recipe draft (200) or maps errors to ApiError."""
    try:
        content_type, data = _decode_file_spec(body)
    except ValueError as exc:
        raise api.ApiError(400, str(exc)) from exc
    try:
        out = _process_file(content_type, data, body.get("filename") or "")
    except ValueError as exc:
        # An unsupported type is a 400; a model failure to extract is a 502 (clean reliability floor).
        msg = str(exc)
        status = 400 if msg.startswith("unsupported contentType") else 502
        raise api.ApiError(status, msg) from exc
    return api.ok(out["draft"])


def _import_multi(files: list, mode: str) -> dict:
    """Multi-file path: per-file results (sync, concurrent) or a batch id (mode=batch)."""
    if not isinstance(files, list) or not files:
        raise api.ApiError(400, "files must be a non-empty array")

    accepted = files[:MAX_FILES]
    overflow = files[MAX_FILES:]

    if mode == "batch":
        batch_id = _submit_batch(accepted)
        return api.ok({"mode": "batch", "batchId": batch_id})

    results: list[dict] = [None] * len(accepted)  # type: ignore[list-item]
    # Parse files concurrently so wall-clock ~= the slowest file (the SDK is synchronous).
    max_workers = max(1, min(len(accepted), MAX_FILES))
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = {pool.submit(_process_file_result, spec): i for i, spec in enumerate(accepted)}
        for fut in concurrent.futures.as_completed(futures):
            results[futures[fut]] = fut.result()

    for spec in overflow:
        name = spec.get("filename") if isinstance(spec, dict) else ""
        results.append(
            {"filename": name or "", "ok": False, "error": f"too many files (max {MAX_FILES})"}
        )

    return api.ok({"results": results, "mode": "sync"})


def _import(user_id: str, event: dict) -> dict:
    """Gate on ``canAiImport``, then dispatch single-file (back-compat) vs multi-file."""
    profile = users.get(user_id, user_id)
    if not profile or not profile.get("canAiImport"):
        return api.error(403, "AI import is not enabled for this account")

    body = api.body(event)
    if "files" in body:
        mode = body.get("mode") or "sync"
        if mode not in ("sync", "batch"):
            raise api.ApiError(400, "mode must be 'sync' or 'batch'")
        return _import_multi(body["files"], mode)
    return _import_single(body)


def _batch_status(user_id: str, batch_id: str) -> dict:
    """GET /recipes/import/batch/{id}: return the batch status/results for an entitled caller."""
    profile = users.get(user_id, user_id)
    if not profile or not profile.get("canAiImport"):
        return api.error(403, "AI import is not enabled for this account")
    return api.ok(_retrieve_batch(batch_id))


@api.route
def handler(event: dict[str, Any], context: Any) -> dict:
    """API Gateway v2 (payload format 2.0) proxy entrypoint; dispatches the import routes."""
    user_id = get_user_id(event)
    method = (event.get("requestContext", {}).get("http", {}) or {}).get("method", "").upper()
    batch_id = api.path_param(event, "id")

    if batch_id is not None:
        if method == "GET":
            return _batch_status(user_id, batch_id)
        return api.error(405, f"method {method or '?'} not allowed on this route")

    if method == "POST":
        return _import(user_id, event)

    return api.error(405, f"method {method or '?'} not allowed on this route")
