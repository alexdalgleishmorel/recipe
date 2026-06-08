"""Unit tests for the admin entitlement handler (#20), against moto-mocked DynamoDB (via `dal`).

Covers: an admin caller flipping another user's canAiImport (true and false); a non-admin caller
getting 403; a target that doesn't exist -> 404; a non-admin being unable to escalate themselves;
and that the caller's isAdmin is read from their STORED profile (not the request body/header). The
handler is invoked the way API Gateway v2 (payload format 2.0) does, with synthetic proxy events.
"""

import json
import os
import sys

import pytest

# Make the admin function module importable without installing it (mirrors test_me_handler.py). The
# `common` + `data_access` layers are already on sys.path via conftest's backend/layers insert.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "admin"))

ADMIN_ID = "user-admin"
ADMIN_EMAIL = "alex.dalgleishmorel@gmail.com"
TARGET_ID = "user-target"
NON_ADMIN_ID = "user-plain"


def _profile(user_id, email, *, is_admin=False, can_ai_import=False):
    """A User.toJson()-shaped dict (user.dart)."""
    return {
        "id": user_id,
        "email": email,
        "displayName": email.split("@", 1)[0],
        "canAiImport": can_ai_import,
        "isAdmin": is_admin,
    }


def _event(user_id, body=None):
    """Build a synthetic API Gateway v2 (payload 2.0) POST event for the admin handler."""
    event = {
        "requestContext": {"http": {"method": "POST"}},
        "headers": {"x-user-id": user_id},
    }
    if body is not None:
        event["body"] = json.dumps(body)
    return event


@pytest.fixture
def admin(dal):
    """Import the admin handler after the moto mock + DAL are active; seed the user profiles.

    The owner is bootstrapped as admin by #13's lazy-create elsewhere; here we seed an admin profile
    directly via the users DAL so the handler reads isAdmin from the stored row.
    """
    from data_access import users

    users.put(ADMIN_ID, _profile(ADMIN_ID, ADMIN_EMAIL, is_admin=True))
    users.put(TARGET_ID, _profile(TARGET_ID, "target@example.com"))
    users.put(NON_ADMIN_ID, _profile(NON_ADMIN_ID, "plain@example.com"))

    import admin as module

    return module


# --- admin can flip another user's canAiImport ----------------------------------------------------
def test_admin_grants_can_ai_import(admin):
    resp = admin.handler(_event(ADMIN_ID, {"userId": TARGET_ID, "canAiImport": True}), None)
    assert resp["statusCode"] == 200
    out = json.loads(resp["body"])
    assert out["id"] == TARGET_ID
    assert out["canAiImport"] is True
    # Persisted.
    from data_access import users

    assert users.get(TARGET_ID, TARGET_ID)["canAiImport"] is True


def test_admin_revokes_can_ai_import(admin):
    from data_access import users

    users.put(TARGET_ID, _profile(TARGET_ID, "target@example.com", can_ai_import=True))
    resp = admin.handler(_event(ADMIN_ID, {"userId": TARGET_ID, "canAiImport": False}), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"])["canAiImport"] is False
    assert users.get(TARGET_ID, TARGET_ID)["canAiImport"] is False


# --- authorization --------------------------------------------------------------------------------
def test_non_admin_caller_is_403(admin):
    resp = admin.handler(_event(NON_ADMIN_ID, {"userId": TARGET_ID, "canAiImport": True}), None)
    assert resp["statusCode"] == 403
    # Target untouched.
    from data_access import users

    assert users.get(TARGET_ID, TARGET_ID)["canAiImport"] is False


def test_non_admin_cannot_escalate_self(admin):
    resp = admin.handler(_event(NON_ADMIN_ID, {"userId": NON_ADMIN_ID, "canAiImport": True}), None)
    assert resp["statusCode"] == 403
    from data_access import users

    assert users.get(NON_ADMIN_ID, NON_ADMIN_ID)["canAiImport"] is False


def test_unknown_caller_is_403(admin):
    """A caller with no stored profile is not admin -> 403 (isAdmin is read from storage, not request)."""
    resp = admin.handler(_event("ghost", {"userId": TARGET_ID, "canAiImport": True}), None)
    assert resp["statusCode"] == 403


# --- target not found -----------------------------------------------------------------------------
def test_target_not_found_is_404(admin):
    resp = admin.handler(_event(ADMIN_ID, {"userId": "does-not-exist", "canAiImport": True}), None)
    assert resp["statusCode"] == 404


# --- validation -----------------------------------------------------------------------------------
def test_missing_user_id_is_400(admin):
    resp = admin.handler(_event(ADMIN_ID, {"canAiImport": True}), None)
    assert resp["statusCode"] == 400


def test_missing_can_ai_import_is_400(admin):
    resp = admin.handler(_event(ADMIN_ID, {"userId": TARGET_ID}), None)
    assert resp["statusCode"] == 400


def test_non_bool_can_ai_import_is_400(admin):
    resp = admin.handler(_event(ADMIN_ID, {"userId": TARGET_ID, "canAiImport": "yes"}), None)
    assert resp["statusCode"] == 400


def test_no_body_is_400(admin):
    resp = admin.handler(_event(ADMIN_ID), None)
    assert resp["statusCode"] == 400


# --- routing --------------------------------------------------------------------------------------
def test_unsupported_method_is_405(admin):
    event = {"requestContext": {"http": {"method": "GET"}}, "headers": {"x-user-id": ADMIN_ID}}
    resp = admin.handler(event, None)
    assert resp["statusCode"] == 405


def test_missing_identity_is_401(admin):
    event = {"requestContext": {"http": {"method": "POST"}}, "headers": {}}
    resp = admin.handler(event, None)
    assert resp["statusCode"] == 401
