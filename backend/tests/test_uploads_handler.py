"""Unit tests for the recipe-image uploads handler (#17), against moto-mocked S3.

Covers the presign happy path (returns an uploadUrl + a caller-scoped key + a publicUrl), that the
object key is prefixed by the caller's userId, that different callers get different prefixes, content
-type validation, and routing/identity guards. The handler is invoked the way API Gateway v2 (payload
format 2.0) does, with synthetic proxy events.
"""

import json
import os
import sys
from urllib.parse import urlparse

import boto3
import pytest
from moto import mock_aws

# Make the common layer + the uploads function module importable without installing them.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "layers"))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "uploads"))

BUCKET = "recipe-uploads-test"
USER_A = "user-aaa"
USER_B = "user-bbb"


def _event(method, user_id, body=None):
    """Build a synthetic API Gateway v2 (payload 2.0) proxy event for the uploads handler."""
    event = {
        "requestContext": {"http": {"method": method}},
        "headers": {"x-user-id": user_id} if user_id else {},
    }
    if body is not None:
        event["body"] = json.dumps(body)
    return event


@pytest.fixture
def uploads(monkeypatch):
    """Yield the uploads handler wired to a fresh moto-mocked S3 bucket for one test."""
    monkeypatch.setenv("UPLOADS_BUCKET", BUCKET)
    with mock_aws():
        boto3.client("s3", region_name="us-east-1").create_bucket(Bucket=BUCKET)

        import uploads as module

        # Reset the lazily-built S3 client so it binds to the active moto backend.
        module._s3 = None
        yield module
        module._s3 = None


def test_presign_returns_url_key_and_public_url(uploads):
    resp = uploads.handler(_event("POST", USER_A, body={"contentType": "image/png"}), None)
    assert resp["statusCode"] == 200
    out = json.loads(resp["body"])
    assert "uploadUrl" in out and "key" in out and "publicUrl" in out
    # The presigned URL is a real https URL pointing at the bucket.
    parsed = urlparse(out["uploadUrl"])
    assert parsed.scheme == "https"
    assert BUCKET in out["uploadUrl"]


def test_key_is_scoped_to_caller(uploads):
    out = json.loads(uploads.handler(_event("POST", USER_A, body={"contentType": "image/png"}), None)["body"])
    assert out["key"].startswith(f"uploads/{USER_A}/")
    assert out["key"].endswith(".png")
    # The public URL embeds the same key.
    assert out["publicUrl"].endswith(out["key"])


def test_different_users_get_different_prefixes(uploads):
    a = json.loads(uploads.handler(_event("POST", USER_A, body={"contentType": "image/jpeg"}), None)["body"])
    b = json.loads(uploads.handler(_event("POST", USER_B, body={"contentType": "image/jpeg"}), None)["body"])
    assert a["key"].startswith(f"uploads/{USER_A}/")
    assert b["key"].startswith(f"uploads/{USER_B}/")
    assert a["key"] != b["key"]


def test_keys_are_unique_per_request(uploads):
    one = json.loads(uploads.handler(_event("POST", USER_A, body={"contentType": "image/png"}), None)["body"])
    two = json.loads(uploads.handler(_event("POST", USER_A, body={"contentType": "image/png"}), None)["body"])
    assert one["key"] != two["key"]


def test_extension_derived_from_content_type(uploads):
    out = json.loads(uploads.handler(_event("POST", USER_A, body={"contentType": "image/webp"}), None)["body"])
    assert out["key"].endswith(".webp")


def test_missing_content_type_defaults_to_jpg(uploads):
    out = json.loads(uploads.handler(_event("POST", USER_A, body={}), None)["body"])
    assert out["key"].endswith(".jpg")


def test_unsupported_content_type_is_400(uploads):
    resp = uploads.handler(_event("POST", USER_A, body={"contentType": "application/pdf"}), None)
    assert resp["statusCode"] == 400


def test_missing_body_is_400(uploads):
    resp = uploads.handler(_event("POST", USER_A), None)
    assert resp["statusCode"] == 400


def test_missing_identity_is_401(uploads):
    resp = uploads.handler(_event("POST", None, body={"contentType": "image/png"}), None)
    assert resp["statusCode"] == 401


def test_unsupported_method_is_405(uploads):
    resp = uploads.handler(_event("GET", USER_A), None)
    assert resp["statusCode"] == 405


def test_missing_bucket_env_is_500(uploads, monkeypatch):
    monkeypatch.delenv("UPLOADS_BUCKET", raising=False)
    resp = uploads.handler(_event("POST", USER_A, body={"contentType": "image/png"}), None)
    assert resp["statusCode"] == 500
