"""Unit tests for the AI recipe-import handler (#19).

The Anthropic call is always mocked — no real API request is made: tests monkeypatch the module-level
``_client`` so ``messages.create`` returns a canned structured-output response. Secrets Manager and S3
are mocked with moto. The users table (the ``canAiImport`` gate) is the conftest ``dal`` fixture's
moto-mocked DynamoDB. The handler is invoked the way API Gateway v2 (payload format 2.0) does, with
synthetic proxy events.

Covers: non-entitled caller -> 403; entitled caller -> parsed Recipe draft (from the mocked response);
the secret is read by name; missing/bad body -> 400; the optional S3 {key} path; routing/identity.
"""

import base64
import json
import os
import sys

import boto3
import pytest
from moto import mock_aws

# Make the common layer + the import_recipe module importable without installing them. The common +
# data_access layers are already on sys.path via conftest's backend/layers insert.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "import_recipe"))

BUCKET = "recipe-uploads-test"
USER_ENTITLED = "user-entitled"
USER_BLOCKED = "user-blocked"

# A 1x1 PNG (valid base64); content is irrelevant since the Anthropic call is mocked.
PNG_B64 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)

# The draft the mocked model "returns" — mirrors the Recipe schema (no id/image).
DRAFT = {
    "title": "Tomato Soup",
    "cuisine": "Italian",
    "description": "A simple soup.",
    "prepTime": 10,
    "cookTime": 25,
    "servings": 4,
    "tags": ["soup"],
    "dietary": ["vegetarian"],
    "author": "Me",
    "ingredients": [{"amount": "2", "unit": "cups", "name": "tomatoes"}],
    "instructions": ["Simmer.", "Blend."],
}


class _TextBlock:
    """Minimal stand-in for an Anthropic text content block."""

    type = "text"

    def __init__(self, text):
        self.text = text


class _Response:
    def __init__(self, text):
        self.content = [_TextBlock(text)]


class _FakeMessages:
    """Records the create() kwargs and returns the canned DRAFT as a JSON text block."""

    def __init__(self, recorder):
        self._recorder = recorder

    def create(self, **kwargs):
        self._recorder.update(kwargs)
        return _Response(json.dumps(DRAFT))


class _FakeAnthropic:
    def __init__(self, recorder):
        self.messages = _FakeMessages(recorder)


def _event(method, user_id, body=None):
    """Build a synthetic API Gateway v2 (payload 2.0) proxy event for the import handler."""
    event = {
        "requestContext": {"http": {"method": method}},
        "headers": {"x-user-id": user_id} if user_id else {},
    }
    if body is not None:
        event["body"] = json.dumps(body)
    return event


def _seed_user(dal, user_id, can_ai_import):
    """Persist a minimal user profile with the given canAiImport flag."""
    dal.users.put(
        user_id,
        {
            "id": user_id,
            "email": f"{user_id}@example.com",
            "displayName": user_id,
            "canAiImport": can_ai_import,
            "isAdmin": False,
        },
    )


@pytest.fixture
def imp(dal, monkeypatch):
    """Yield the import handler with moto Secrets Manager + S3 and a stubbed Anthropic client.

    ``imp.create_calls`` captures the kwargs passed to ``messages.create`` so tests can assert the
    structured-output config and file block. The dal fixture already has the moto DynamoDB mock active.
    """
    monkeypatch.setenv("UPLOADS_BUCKET", BUCKET)

    import import_recipe as module

    # Secrets Manager + S3 share the dal fixture's active moto mock (mock_aws is reentrant).
    sm = boto3.client("secretsmanager", region_name="us-east-1")
    sm.create_secret(Name=module.ANTHROPIC_SECRET_NAME, SecretString="sk-ant-test-key")
    boto3.client("s3", region_name="us-east-1").create_bucket(Bucket=BUCKET)

    # Reset lazily-built clients so they bind to the active moto backends.
    module._secrets_client = None
    module._s3_client = None
    module._anthropic_client = None

    create_calls = {}

    # Stub the Anthropic client so NO real API request is made; still exercises _api_key() (Secrets).
    def fake_client():
        module._api_key()  # ensure the secret is read by name (raises if missing/denied)
        return _FakeAnthropic(create_calls)

    monkeypatch.setattr(module, "_client", fake_client)

    module.create_calls = create_calls
    yield module

    module._secrets_client = None
    module._s3_client = None
    module._anthropic_client = None


# --- entitlement gate -----------------------------------------------------------------------------
def test_non_entitled_caller_is_403(imp, dal):
    _seed_user(dal, USER_BLOCKED, can_ai_import=False)
    resp = imp.handler(
        _event("POST", USER_BLOCKED, body={"contentBase64": PNG_B64, "contentType": "image/png"}),
        None,
    )
    assert resp["statusCode"] == 403


def test_missing_profile_is_403(imp, dal):
    # No profile row at all -> treated as not entitled.
    resp = imp.handler(
        _event("POST", "user-unknown", body={"contentBase64": PNG_B64, "contentType": "image/png"}),
        None,
    )
    assert resp["statusCode"] == 403


# --- happy path -----------------------------------------------------------------------------------
def test_entitled_caller_gets_recipe_draft(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    resp = imp.handler(
        _event("POST", USER_ENTITLED, body={"contentBase64": PNG_B64, "contentType": "image/png"}),
        None,
    )
    assert resp["statusCode"] == 200
    out = json.loads(resp["body"])
    assert out == DRAFT
    # No id is assigned here (the frontend saves via POST /recipes).
    assert "id" not in out


def test_create_uses_structured_output_and_image_block(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    imp.handler(
        _event("POST", USER_ENTITLED, body={"contentBase64": PNG_B64, "contentType": "image/png"}),
        None,
    )
    call = imp.create_calls
    assert call["model"] == "claude-opus-4-8"
    fmt = call["output_config"]["format"]
    assert fmt["type"] == "json_schema"
    assert fmt["schema"] == imp.RECIPE_JSON_SCHEMA
    block = call["messages"][0]["content"][0]
    assert block["type"] == "image"
    assert block["source"]["media_type"] == "image/png"
    assert block["source"]["data"] == PNG_B64


def test_pdf_uses_document_block(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    imp.handler(
        _event(
            "POST",
            USER_ENTITLED,
            body={"contentBase64": PNG_B64, "contentType": "application/pdf"},
        ),
        None,
    )
    block = imp.create_calls["messages"][0]["content"][0]
    assert block["type"] == "document"
    assert block["source"]["media_type"] == "application/pdf"


# --- secret is read by name -----------------------------------------------------------------------
def test_secret_read_by_name(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    # Build the real Anthropic client path far enough to read the secret, but stub the SDK class so no
    # network call happens. _api_key() must request the secret by ANTHROPIC_SECRET_NAME.
    import import_recipe as module

    requested = {}
    real_get = module._secrets().get_secret_value

    def spy(SecretId):  # noqa: N803 - boto3 kwarg name
        requested["id"] = SecretId
        return real_get(SecretId=SecretId)

    module._secrets().get_secret_value = spy
    assert module._api_key() == "sk-ant-test-key"
    assert requested["id"] == module.ANTHROPIC_SECRET_NAME


def test_secret_json_blob_is_supported(imp, dal):
    import import_recipe as module

    sm = boto3.client("secretsmanager", region_name="us-east-1")
    sm.put_secret_value(
        SecretId=module.ANTHROPIC_SECRET_NAME,
        SecretString=json.dumps({"apiKey": "sk-ant-json"}),
    )
    assert module._api_key() == "sk-ant-json"


# --- S3 {key} path --------------------------------------------------------------------------------
def test_key_path_fetches_from_s3(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    key = f"uploads/{USER_ENTITLED}/photo.png"
    boto3.client("s3", region_name="us-east-1").put_object(
        Bucket=BUCKET,
        Key=key,
        Body=base64.b64decode(PNG_B64),
        ContentType="image/png",
    )
    resp = imp.handler(_event("POST", USER_ENTITLED, body={"key": key}), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == DRAFT
    # The bytes from S3 were base64-encoded into the image block.
    block = imp.create_calls["messages"][0]["content"][0]
    assert block["type"] == "image"
    assert block["source"]["data"] == PNG_B64


# --- body / input validation ----------------------------------------------------------------------
def test_missing_body_is_400(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    resp = imp.handler(_event("POST", USER_ENTITLED), None)
    assert resp["statusCode"] == 400


def test_missing_content_is_400(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    resp = imp.handler(_event("POST", USER_ENTITLED, body={"contentType": "image/png"}), None)
    assert resp["statusCode"] == 400


def test_bad_base64_is_400(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    resp = imp.handler(
        _event("POST", USER_ENTITLED, body={"contentBase64": "not!base64!", "contentType": "image/png"}),
        None,
    )
    assert resp["statusCode"] == 400


def test_unsupported_content_type_is_400(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    resp = imp.handler(
        _event(
            "POST",
            USER_ENTITLED,
            body={"contentBase64": PNG_B64, "contentType": "text/plain"},
        ),
        None,
    )
    assert resp["statusCode"] == 400


# --- routing / identity ---------------------------------------------------------------------------
def test_missing_identity_is_401(imp, dal):
    resp = imp.handler(
        _event("POST", None, body={"contentBase64": PNG_B64, "contentType": "image/png"}),
        None,
    )
    assert resp["statusCode"] == 401


def test_unsupported_method_is_405(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    resp = imp.handler(_event("GET", USER_ENTITLED), None)
    assert resp["statusCode"] == 405
