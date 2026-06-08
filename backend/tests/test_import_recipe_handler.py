"""Unit tests for the cost-optimized AI recipe-import handler (#76).

The Anthropic call is always mocked via the module-level ``_client`` seam — no real API request is
made. The JSON tier (jsonschema) and the image tier's Pillow downsize run for real (pure Python).
Secrets Manager and S3 are mocked with moto; the users table (the ``canAiImport`` gate) is the
conftest ``dal`` fixture's moto-mocked DynamoDB. The handler is invoked the way API Gateway v2
(payload format 2.0) does, with synthetic proxy events.

Covers: entitlement gate; back-compat single-file draft; tiered routing (JSON -> no AI; image ->
haiku; haiku-incomplete -> Sonnet fallback); off-schema JSON -> ok:false; multi-file per-file
results mixing ok/error; cost-log fields populated; structured-output + cached system block; the
count_tokens estimator; the secret is read by name.
"""

import base64
import io
import json
import os
import sys

import boto3
import pytest

# Make the import_recipe module importable without installing it. The common + data_access layers are
# already on sys.path via conftest's backend/layers insert.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "import_recipe"))

BUCKET = "recipe-uploads-test"
USER_ENTITLED = "user-entitled"
USER_BLOCKED = "user-blocked"


def _png_bytes(w=8, h=8):
    """Return raw bytes of a small valid PNG (Pillow opens/re-encodes it in the image tier)."""
    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (w, h), (200, 100, 50)).save(buf, format="PNG")
    return buf.getvalue()


def _png_b64(w=8, h=8):
    return base64.b64encode(_png_bytes(w, h)).decode("ascii")


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

# An incomplete draft (no instructions) -> fails the completeness gate.
INCOMPLETE_DRAFT = {**DRAFT, "instructions": []}


class _TextBlock:
    type = "text"

    def __init__(self, text):
        self.text = text


class _Usage:
    def __init__(self, **kw):
        self.input_tokens = kw.get("input_tokens", 0)
        self.output_tokens = kw.get("output_tokens", 0)
        self.cache_read_input_tokens = kw.get("cache_read_input_tokens", 0)
        self.cache_creation_input_tokens = kw.get("cache_creation_input_tokens", 0)


class _Response:
    def __init__(self, text, usage=None):
        self.content = [_TextBlock(text)]
        self.usage = usage or _Usage(input_tokens=1200, output_tokens=300, cache_read_input_tokens=900)


class _CountTokens:
    def __init__(self, value):
        self.input_tokens = value


class _FakeMessages:
    """Records create() kwargs per call; returns a per-model canned draft (keyed by substring)."""

    def __init__(self, recorder, by_model):
        self._recorder = recorder
        self._by_model = by_model

    def create(self, **kwargs):
        self._recorder.setdefault("calls", []).append(kwargs)
        self._recorder.update(kwargs)  # last-call convenience for single-file assertions
        draft = self._by_model.get(kwargs["model"], DRAFT)
        return _Response(json.dumps(draft))

    def count_tokens(self, **kwargs):
        self._recorder.setdefault("count_calls", []).append(kwargs)
        return _CountTokens(4321)


class _FakeAnthropic:
    def __init__(self, recorder, by_model):
        self.messages = _FakeMessages(recorder, by_model)


def _event(method, user_id, body=None, path_id=None):
    """Build a synthetic API Gateway v2 (payload 2.0) proxy event for the import handler."""
    event = {
        "requestContext": {"http": {"method": method}},
        "headers": {"x-user-id": user_id} if user_id else {},
    }
    if body is not None:
        event["body"] = json.dumps(body)
    if path_id is not None:
        event["pathParameters"] = {"id": path_id}
    return event


def _seed_user(dal, user_id, can_ai_import):
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

    ``imp.recorder`` captures messages.create kwargs (last call + the ``calls`` list) and
    count_tokens calls. ``imp.by_model`` maps model id -> the draft that model "returns"; tests
    mutate it to drive the fallback path.
    """
    monkeypatch.setenv("UPLOADS_BUCKET", BUCKET)

    import import_recipe as module

    sm = boto3.client("secretsmanager", region_name="us-east-1")
    sm.create_secret(Name=module.ANTHROPIC_SECRET_NAME, SecretString="sk-ant-test-key")
    boto3.client("s3", region_name="us-east-1").create_bucket(Bucket=BUCKET)

    module._secrets_client = None
    module._s3_client = None
    module._anthropic_client = None

    recorder = {}
    by_model = {}

    def fake_client():
        module._api_key()  # ensure the secret is read by name (raises if missing/denied)
        return _FakeAnthropic(recorder, by_model)

    monkeypatch.setattr(module, "_client", fake_client)

    module.recorder = recorder
    module.by_model = by_model
    yield module

    module._secrets_client = None
    module._s3_client = None
    module._anthropic_client = None


# --- entitlement gate -----------------------------------------------------------------------------
def test_non_entitled_caller_is_403(imp, dal):
    _seed_user(dal, USER_BLOCKED, can_ai_import=False)
    resp = imp.handler(
        _event("POST", USER_BLOCKED, body={"contentBase64": _png_b64(), "contentType": "image/png"}),
        None,
    )
    assert resp["statusCode"] == 403


def test_missing_profile_is_403(imp, dal):
    resp = imp.handler(
        _event("POST", "user-unknown", body={"contentBase64": _png_b64(), "contentType": "image/png"}),
        None,
    )
    assert resp["statusCode"] == 403


# --- back-compat single-file path -----------------------------------------------------------------
def test_single_file_returns_a_single_draft(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    resp = imp.handler(
        _event("POST", USER_ENTITLED, body={"contentBase64": _png_b64(), "contentType": "image/png"}),
        None,
    )
    assert resp["statusCode"] == 200
    out = json.loads(resp["body"])
    assert out == DRAFT
    assert "id" not in out  # the frontend saves via POST /recipes


def test_structured_output_and_cached_system_block(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    imp.handler(
        _event("POST", USER_ENTITLED, body={"contentBase64": _png_b64(), "contentType": "image/png"}),
        None,
    )
    call = imp.recorder
    assert call["model"] == "claude-haiku-4-5"  # PRIMARY_MODEL default; never Opus
    fmt = call["output_config"]["format"]
    assert fmt["type"] == "json_schema"
    assert fmt["schema"] == imp.RECIPE_JSON_SCHEMA
    # Static system block carries the ephemeral cache_control marker.
    assert call["system"][0]["cache_control"] == {"type": "ephemeral"}
    # The image block is sent (re-encoded as PNG by the Pillow downsize step).
    block = call["messages"][0]["content"][0]
    assert block["type"] == "image"
    assert block["source"]["media_type"] == "image/png"


# --- tiered routing: image -> haiku ---------------------------------------------------------------
def test_image_uses_haiku_tier(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    resp = imp.handler(
        _event(
            "POST",
            USER_ENTITLED,
            body={"files": [{"contentBase64": _png_b64(), "contentType": "image/png", "filename": "a.png"}]},
        ),
        None,
    )
    assert resp["statusCode"] == 200
    results = json.loads(resp["body"])["results"]
    assert results[0]["ok"] is True
    assert results[0]["tier"] == "haiku"
    assert results[0]["draft"] == DRAFT


# --- reliability gate: haiku incomplete -> Sonnet fallback ----------------------------------------
def test_haiku_incomplete_falls_back_to_sonnet(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    imp.by_model["claude-haiku-4-5"] = INCOMPLETE_DRAFT  # Haiku returns an incomplete draft
    imp.by_model["claude-sonnet-4-6"] = DRAFT  # Sonnet rescues it
    resp = imp.handler(
        _event(
            "POST",
            USER_ENTITLED,
            body={"files": [{"contentBase64": _png_b64(), "contentType": "image/png", "filename": "a.png"}]},
        ),
        None,
    )
    results = json.loads(resp["body"])["results"]
    assert results[0]["ok"] is True
    assert results[0]["tier"] == "sonnet"
    models = [c["model"] for c in imp.recorder["calls"]]
    assert models == ["claude-haiku-4-5", "claude-sonnet-4-6"]


def test_both_models_incomplete_is_clean_error(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    imp.by_model["claude-haiku-4-5"] = INCOMPLETE_DRAFT
    imp.by_model["claude-sonnet-4-6"] = INCOMPLETE_DRAFT
    resp = imp.handler(
        _event(
            "POST",
            USER_ENTITLED,
            body={"files": [{"contentBase64": _png_b64(), "contentType": "image/png", "filename": "a.png"}]},
        ),
        None,
    )
    results = json.loads(resp["body"])["results"]
    assert results[0]["ok"] is False
    assert "complete" in results[0]["error"]


def test_single_file_model_failure_is_502(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    imp.by_model["claude-haiku-4-5"] = INCOMPLETE_DRAFT
    imp.by_model["claude-sonnet-4-6"] = INCOMPLETE_DRAFT
    resp = imp.handler(
        _event("POST", USER_ENTITLED, body={"contentBase64": _png_b64(), "contentType": "image/png"}),
        None,
    )
    assert resp["statusCode"] == 502


# --- JSON tier: accepted, no Anthropic call -------------------------------------------------------
def test_valid_json_upload_accepted_no_ai_call(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    payload = base64.b64encode(json.dumps(DRAFT).encode("utf-8")).decode("ascii")
    resp = imp.handler(
        _event(
            "POST",
            USER_ENTITLED,
            body={"files": [{"contentBase64": payload, "contentType": "application/json", "filename": "r.json"}]},
        ),
        None,
    )
    results = json.loads(resp["body"])["results"]
    assert results[0]["ok"] is True
    assert results[0]["tier"] == "json"
    assert results[0]["draft"] == DRAFT
    # No Anthropic call was made for the JSON tier.
    assert "calls" not in imp.recorder


def test_offschema_json_is_per_file_error(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    bad = {"title": "x", "extra": "nope"}  # missing required fields + additionalProperties
    payload = base64.b64encode(json.dumps(bad).encode("utf-8")).decode("ascii")
    resp = imp.handler(
        _event(
            "POST",
            USER_ENTITLED,
            body={"files": [{"contentBase64": payload, "contentType": "application/json", "filename": "r.json"}]},
        ),
        None,
    )
    results = json.loads(resp["body"])["results"]
    assert results[0]["ok"] is False
    assert results[0]["error"].startswith("off-schema")
    assert "calls" not in imp.recorder  # still no AI call


# --- multi-file: per-file results mixing ok/error -------------------------------------------------
def test_multi_file_mixed_ok_and_error(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    good_json = base64.b64encode(json.dumps(DRAFT).encode("utf-8")).decode("ascii")
    resp = imp.handler(
        _event(
            "POST",
            USER_ENTITLED,
            body={
                "files": [
                    {"contentBase64": _png_b64(), "contentType": "image/png", "filename": "photo.png"},
                    {"contentBase64": good_json, "contentType": "application/json", "filename": "r.json"},
                    {"contentBase64": _png_b64(), "contentType": "text/plain", "filename": "bad.txt"},
                ]
            },
        ),
        None,
    )
    body = json.loads(resp["body"])
    assert body["mode"] == "sync"
    results = {r["filename"]: r for r in body["results"]}
    assert results["photo.png"]["ok"] is True and results["photo.png"]["tier"] == "haiku"
    assert results["r.json"]["ok"] is True and results["r.json"]["tier"] == "json"
    assert results["bad.txt"]["ok"] is False
    assert "unsupported" in results["bad.txt"]["error"]


def test_multi_file_cap_overflow_is_per_file_error(imp, dal, monkeypatch):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    monkeypatch.setattr(imp, "MAX_FILES", 2)
    files = [
        {"contentBase64": _png_b64(), "contentType": "image/png", "filename": f"f{i}.png"}
        for i in range(4)
    ]
    resp = imp.handler(_event("POST", USER_ENTITLED, body={"files": files}), None)
    assert resp["statusCode"] == 200  # not a 400 of the whole request
    results = json.loads(resp["body"])["results"]
    assert len(results) == 4
    assert sum(1 for r in results if r["ok"]) == 2
    overflow = [r for r in results if not r["ok"]]
    assert all("too many files" in r["error"] for r in overflow)


# --- cost instrumentation -------------------------------------------------------------------------
def test_cost_log_fields_populated(imp, dal, caplog):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    import logging

    with caplog.at_level(logging.INFO, logger="import_recipe"):
        imp.handler(
            _event("POST", USER_ENTITLED, body={"contentBase64": _png_b64(), "contentType": "image/png"}),
            None,
        )
    records = [json.loads(r.message) for r in caplog.records if r.name == "import_recipe"]
    assert records, "expected a recipe_import log line"
    rec = records[-1]
    assert rec["event"] == "recipe_import"
    assert rec["tier"] == "haiku"
    assert rec["model"] == "claude-haiku-4-5"
    assert rec["mode"] == "sync"
    assert rec["input_tokens"] == 1200
    assert rec["output_tokens"] == 300
    assert rec["cache_read_input_tokens"] == 900
    # Haiku default rates: 1/MTok in, 5/MTok out -> (1200*1 + 300*5)/1e6.
    assert rec["cost_usd"] == pytest.approx((1200 * 1 + 300 * 5) / 1_000_000.0)


def test_json_tier_logs_zero_cost(imp, dal, caplog):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    import logging

    payload = base64.b64encode(json.dumps(DRAFT).encode("utf-8")).decode("ascii")
    with caplog.at_level(logging.INFO, logger="import_recipe"):
        imp.handler(
            _event(
                "POST",
                USER_ENTITLED,
                body={"files": [{"contentBase64": payload, "contentType": "application/json", "filename": "r.json"}]},
            ),
            None,
        )
    rec = [json.loads(r.message) for r in caplog.records if r.name == "import_recipe"][-1]
    assert rec["tier"] == "json"
    assert rec["cost_usd"] == 0.0
    assert rec["model"] is None


def test_count_tokens_estimator(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    n = imp.estimate_input_tokens("image/png", _png_bytes())
    assert n == 4321
    assert imp.recorder["count_calls"], "count_tokens should have been called"
    # The estimator sends the cached system block too.
    assert imp.recorder["count_calls"][0]["system"][0]["cache_control"] == {"type": "ephemeral"}


# --- batch mode -----------------------------------------------------------------------------------
def test_batch_mode_returns_batch_id(imp, dal, monkeypatch):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)

    class _Batches:
        def __init__(self):
            self.submitted = None

        def create(self, requests):
            self.submitted = requests
            return {"id": "batch_abc123"}

    batches = _Batches()

    def fake_client():
        c = _FakeAnthropic(imp.recorder, imp.by_model)
        c.messages.batches = batches
        return c

    monkeypatch.setattr(imp, "_client", fake_client)
    resp = imp.handler(
        _event(
            "POST",
            USER_ENTITLED,
            body={
                "mode": "batch",
                "files": [{"contentBase64": _png_b64(), "contentType": "image/png", "filename": "a.png"}],
            },
        ),
        None,
    )
    body = json.loads(resp["body"])
    assert body == {"mode": "batch", "batchId": "batch_abc123"}
    assert len(batches.submitted) == 1
    assert batches.submitted[0]["params"]["model"] == "claude-haiku-4-5"


def test_batch_status_route(imp, dal, monkeypatch):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)

    class _Batches:
        def retrieve(self, batch_id):
            return {"id": batch_id, "processing_status": "in_progress"}

    def fake_client():
        c = _FakeAnthropic(imp.recorder, imp.by_model)
        c.messages.batches = _Batches()
        return c

    monkeypatch.setattr(imp, "_client", fake_client)
    resp = imp.handler(_event("GET", USER_ENTITLED, path_id="batch_abc123"), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == {"batchId": "batch_abc123", "status": "in_progress"}


# --- secret is read by name -----------------------------------------------------------------------
def test_secret_read_by_name(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
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
        Body=_png_bytes(),
        ContentType="image/png",
    )
    resp = imp.handler(_event("POST", USER_ENTITLED, body={"key": key}), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == DRAFT


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


def test_unsupported_content_type_single_is_400(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    resp = imp.handler(
        _event("POST", USER_ENTITLED, body={"contentBase64": _png_b64(), "contentType": "text/plain"}),
        None,
    )
    assert resp["statusCode"] == 400


# --- routing / identity ---------------------------------------------------------------------------
def test_missing_identity_is_401(imp, dal):
    resp = imp.handler(
        _event("POST", None, body={"contentBase64": _png_b64(), "contentType": "image/png"}),
        None,
    )
    assert resp["statusCode"] == 401


def test_unsupported_method_is_405(imp, dal):
    _seed_user(dal, USER_ENTITLED, can_ai_import=True)
    resp = imp.handler(_event("GET", USER_ENTITLED), None)
    assert resp["statusCode"] == 405
