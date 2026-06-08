"""Recipe-image upload handler (#17) — copies the recipes/me Lambda dispatch pattern.

Recipe images are stored in a private S3 bucket; the browser uploads the bytes directly to S3 via a
short-lived presigned PUT URL, and the recipe stores the object key/URL in ``recipe.image``. This
keeps image bytes off the API Lambda (the request only mints a URL):

    POST /uploads/presign  -> { uploadUrl, key, publicUrl }

The caller sends a small JSON body with the file's ``contentType`` (e.g. ``{"contentType":
"image/png"}``); the handler derives the object extension from it, generates an object key scoped to
the caller (``uploads/<userId>/<uuid>.<ext>``), and returns a boto3 ``put_object`` presigned URL
(short expiry) plus the object's key and URL. Every key is scoped by ``common.get_user_id`` so a
caller can only ever mint URLs under their own prefix. A single ``handler`` dispatches the one route.

The bucket name comes from the ``UPLOADS_BUCKET`` env var (set in Terraform's lambda_env). The client
then PUTs the file bytes to ``uploadUrl`` with the same ``Content-Type`` and stores ``publicUrl`` (or
``key``) in the recipe — reads are served via a presigned GET or a CloudFront/object URL later.

TODO(#11): once the Cognito JWT authorizer is attached, the route flips to auth = true; identity
already comes from ``common.get_user_id`` (JWT ``sub``), so no handler change is needed.
"""

from __future__ import annotations

import os
import uuid
from typing import Any

import boto3

from common import api, get_user_id

# Env var carrying the private uploads bucket name (set from Terraform lambda_env / UPLOADS_BUCKET).
BUCKET_ENV = "UPLOADS_BUCKET"

# Presigned URL lifetime in seconds — short, since the browser uploads immediately after minting.
PRESIGN_EXPIRY_SECONDS = 300

# Key prefix under which every caller's uploads live; the userId segment isolates callers.
KEY_PREFIX = "uploads"

# Content types we mint upload URLs for, mapped to the object-key extension. Restricting to images
# keeps the bucket to its purpose (recipe photos) and gives us a sensible default extension.
CONTENT_TYPE_EXTENSIONS = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "image/gif": "gif",
    "image/heic": "heic",
}

DEFAULT_CONTENT_TYPE = "image/jpeg"

_s3 = None


def _client():
    """Return the boto3 S3 client, built lazily so importing the module needs no AWS creds/region."""
    global _s3
    if _s3 is None:
        _s3 = boto3.client("s3")
    return _s3


def _bucket() -> str:
    """Return the configured uploads bucket name; raise a 500-mapping error if unset."""
    bucket = os.environ.get(BUCKET_ENV)
    if not bucket:
        raise api.ApiError(500, f"{BUCKET_ENV} is not configured")
    return bucket


def _extension(content_type: str) -> str:
    """Map a content type to an object-key extension, defaulting to ``jpg`` for unknown image types."""
    return CONTENT_TYPE_EXTENSIONS.get(content_type.lower().strip(), "jpg")


def _public_url(bucket: str, key: str) -> str:
    """Build the canonical S3 object URL for ``key`` (region-aware virtual-hosted style)."""
    region = _client().meta.region_name or "us-east-1"
    if region == "us-east-1":
        return f"https://{bucket}.s3.amazonaws.com/{key}"
    return f"https://{bucket}.s3.{region}.amazonaws.com/{key}"


def _presign(user_id: str, event: dict) -> dict:
    """Mint a presigned PUT URL for a new, caller-scoped object key."""
    body = api.body(event)
    content_type = body.get("contentType") or DEFAULT_CONTENT_TYPE
    if not isinstance(content_type, str):
        return api.bad_request("contentType must be a string")
    if content_type.lower().strip() not in CONTENT_TYPE_EXTENSIONS:
        return api.bad_request(f"unsupported contentType '{content_type}'")

    bucket = _bucket()
    key = f"{KEY_PREFIX}/{user_id}/{uuid.uuid4().hex}.{_extension(content_type)}"

    upload_url = _client().generate_presigned_url(
        "put_object",
        Params={"Bucket": bucket, "Key": key, "ContentType": content_type},
        ExpiresIn=PRESIGN_EXPIRY_SECONDS,
    )

    return api.ok(
        {
            "uploadUrl": upload_url,
            "key": key,
            "publicUrl": _public_url(bucket, key),
        }
    )


@api.route
def handler(event: dict[str, Any], context: Any) -> dict:
    """API Gateway v2 (payload format 2.0) proxy entrypoint; dispatches the presign route."""
    user_id = get_user_id(event)
    method = (event.get("requestContext", {}).get("http", {}) or {}).get("method", "").upper()

    if method == "POST":
        return _presign(user_id, event)

    return api.error(405, f"method {method or '?'} not allowed on this route")
