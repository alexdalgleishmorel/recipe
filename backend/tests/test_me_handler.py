"""Unit tests for the user profile handler (#13), against moto-mocked DynamoDB (via the `dal` fixture).

Covers lazy-create on the first GET, idempotency on the second, admin-email -> isAdmin, the PUT
update path (displayName changes; isAdmin/canAiImport can't be escalated), and per-user scoping. The
handler is invoked the way API Gateway v2 (payload format 2.0) does, with synthetic proxy events.
"""

import json
import os
import sys

import pytest

# Make the me function module importable without installing it (mirrors test_recipes_handler.py). The
# `common` + `data_access` layers are already on sys.path via conftest's backend/layers insert.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "me"))

ADMIN_EMAIL = "alex.dalgleishmorel@gmail.com"
USER_A = "user-aaa"
USER_B = "user-bbb"


def _event(method, user_id, email=None, body=None):
    """Build a synthetic API Gateway v2 (payload 2.0) proxy event for the me handler."""
    headers = {"x-user-id": user_id}
    if email is not None:
        headers["x-user-email"] = email
    event = {
        "requestContext": {"http": {"method": method}},
        "headers": headers,
    }
    if body is not None:
        event["body"] = json.dumps(body)
    return event


@pytest.fixture
def me(dal, monkeypatch):
    """Import the me handler after the moto mock + DAL are active, with ADMIN_EMAIL set."""
    monkeypatch.setenv("ADMIN_EMAIL", ADMIN_EMAIL)
    import me as module

    return module


# --- lazy create ----------------------------------------------------------------------------------
def test_get_lazy_creates_profile(me):
    resp = me.handler(_event("GET", USER_A, email="someone@example.com"), None)
    assert resp["statusCode"] == 200
    profile = json.loads(resp["body"])
    assert profile["id"] == USER_A
    assert profile["email"] == "someone@example.com"
    assert profile["displayName"] == "someone"  # email local-part
    assert profile["canAiImport"] is False
    assert profile["isAdmin"] is False


def test_get_is_idempotent(me):
    first = json.loads(me.handler(_event("GET", USER_A, email="x@example.com"), None)["body"])
    second = json.loads(me.handler(_event("GET", USER_A, email="x@example.com"), None)["body"])
    assert first == second


def test_get_idempotent_preserves_existing_profile(me):
    # First GET creates the profile, then a PUT renames it.
    me.handler(_event("GET", USER_A, email="x@example.com"), None)
    me.handler(_event("PUT", USER_A, body={"displayName": "Renamed"}), None)
    # A subsequent GET must return the stored (renamed) profile, not re-create a fresh one.
    again = json.loads(me.handler(_event("GET", USER_A, email="x@example.com"), None)["body"])
    assert again["displayName"] == "Renamed"


def test_uses_name_claim_for_display_name_when_present(me):
    event = _event("GET", USER_A, email="x@example.com")
    event["requestContext"]["authorizer"] = {"jwt": {"claims": {"sub": USER_A, "name": "Jane Doe"}}}
    profile = json.loads(me.handler(event, None)["body"])
    assert profile["displayName"] == "Jane Doe"


def test_email_from_jwt_claim_takes_precedence(me):
    event = _event("GET", USER_A, email="header@example.com")
    event["requestContext"]["authorizer"] = {"jwt": {"claims": {"sub": USER_A, "email": "jwt@example.com"}}}
    profile = json.loads(me.handler(event, None)["body"])
    assert profile["email"] == "jwt@example.com"


# --- admin entitlement ----------------------------------------------------------------------------
def test_admin_email_gets_is_admin_true(me):
    profile = json.loads(me.handler(_event("GET", USER_A, email=ADMIN_EMAIL), None)["body"])
    assert profile["isAdmin"] is True


def test_admin_email_is_case_insensitive(me):
    profile = json.loads(me.handler(_event("GET", USER_A, email=ADMIN_EMAIL.upper()), None)["body"])
    assert profile["isAdmin"] is True


def test_non_admin_email_gets_is_admin_false(me):
    profile = json.loads(me.handler(_event("GET", USER_A, email="nope@example.com"), None)["body"])
    assert profile["isAdmin"] is False


def test_no_email_is_not_admin(me):
    profile = json.loads(me.handler(_event("GET", USER_A), None)["body"])
    assert profile["isAdmin"] is False
    assert profile["email"] == ""


# --- PUT update -----------------------------------------------------------------------------------
def test_put_updates_display_name(me):
    me.handler(_event("GET", USER_A, email="x@example.com"), None)
    resp = me.handler(_event("PUT", USER_A, body={"displayName": "New Name"}), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"])["displayName"] == "New Name"
    # Persisted.
    again = json.loads(me.handler(_event("GET", USER_A, email="x@example.com"), None)["body"])
    assert again["displayName"] == "New Name"


def test_put_cannot_escalate_is_admin(me):
    me.handler(_event("GET", USER_A, email="nope@example.com"), None)
    resp = me.handler(_event("PUT", USER_A, body={"displayName": "X", "isAdmin": True}), None)
    assert json.loads(resp["body"])["isAdmin"] is False


def test_put_cannot_grant_can_ai_import(me):
    me.handler(_event("GET", USER_A, email="nope@example.com"), None)
    resp = me.handler(_event("PUT", USER_A, body={"canAiImport": True}), None)
    assert json.loads(resp["body"])["canAiImport"] is False


def test_put_cannot_change_id_or_email(me):
    me.handler(_event("GET", USER_A, email="x@example.com"), None)
    resp = me.handler(
        _event("PUT", USER_A, body={"id": "hacked", "email": "hacked@example.com"}), None
    )
    out = json.loads(resp["body"])
    assert out["id"] == USER_A
    assert out["email"] == "x@example.com"


def test_put_without_existing_profile_lazy_creates(me):
    resp = me.handler(_event("PUT", USER_A, email="x@example.com", body={"displayName": "First"}), None)
    assert resp["statusCode"] == 200
    out = json.loads(resp["body"])
    assert out["id"] == USER_A
    assert out["displayName"] == "First"


def test_put_without_body_is_400(me):
    resp = me.handler(_event("PUT", USER_A), None)
    assert resp["statusCode"] == 400


# --- per-user scoping -----------------------------------------------------------------------------
def test_profiles_are_per_user(me):
    a = json.loads(me.handler(_event("GET", USER_A, email="a@example.com"), None)["body"])
    b = json.loads(me.handler(_event("GET", USER_B, email="b@example.com"), None)["body"])
    assert a["id"] == USER_A and a["email"] == "a@example.com"
    assert b["id"] == USER_B and b["email"] == "b@example.com"


def test_put_does_not_touch_another_users_profile(me):
    me.handler(_event("GET", USER_A, email="a@example.com"), None)
    me.handler(_event("GET", USER_B, email="b@example.com"), None)
    me.handler(_event("PUT", USER_B, body={"displayName": "B Renamed"}), None)
    a_view = json.loads(me.handler(_event("GET", USER_A, email="a@example.com"), None)["body"])
    assert a_view["displayName"] == "a"  # unchanged (email local-part)


# --- identity + routing ---------------------------------------------------------------------------
def test_missing_identity_is_401(me):
    event = {"requestContext": {"http": {"method": "GET"}}, "headers": {}}
    resp = me.handler(event, None)
    assert resp["statusCode"] == 401


def test_unsupported_method_is_405(me):
    resp = me.handler(_event("DELETE", USER_A), None)
    assert resp["statusCode"] == 405
