"""Unit tests for the collections CRUD handler (#16), against moto-mocked DynamoDB (via `dal`).

Covers each route (list/create/get/update/delete), server-assigned ids, and per-user scoping (a user
can neither read, update, nor delete another user's collection). The handler is invoked the way API
Gateway v2 (payload format 2.0) does, with synthetic proxy events. Mirrors test_plans_handler.py.
"""

import importlib.util
import json
import os
import sys

import pytest

# The handler module is named collections_api.py (deliberately NOT collections.py, which would shadow
# the Python stdlib `collections` package at import time). We still load it from its path for symmetry
# with the other handler tests. The `common` + `data_access` layers are on sys.path via conftest's
# backend/layers insert; the function dir is added so the handler's `from common ...`/`from
# data_access ...` resolve.
_FN_DIR = os.path.join(os.path.dirname(__file__), "..", "functions", "collections")
sys.path.insert(0, _FN_DIR)

USER_A = "user-aaa"
USER_B = "user-bbb"


def _load_collections_module():
    """Load functions/collections/collections_api.py as `collections_api`."""
    spec = importlib.util.spec_from_file_location(
        "collections_api", os.path.join(_FN_DIR, "collections_api.py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _collection(name="Test Collection"):
    """A Collection.toJson()-shaped dict (collection.dart) without an id (the server assigns it)."""
    return {
        "name": name,
        "description": "A handful of go-to recipes.",
        "recipeIds": ["r1", "r2", "r3"],
    }


def _event(method, user_id, collection_id=None, body=None):
    """Build a synthetic API Gateway v2 (payload 2.0) proxy event for the collections handler."""
    event = {
        "requestContext": {"http": {"method": method}},
        "headers": {"x-user-id": user_id},
    }
    if collection_id is not None:
        event["pathParameters"] = {"id": collection_id}
    if body is not None:
        event["body"] = json.dumps(body)
    return event


@pytest.fixture
def collections(dal):
    """Load the collections handler after the moto mock + DAL are active."""
    return _load_collections_module()


def _create(collections, user_id, body=None):
    resp = collections.handler(_event("POST", user_id, body=body or _collection()), None)
    assert resp["statusCode"] == 201
    return json.loads(resp["body"])


# --- create + server-assigned ids -----------------------------------------------------------------
def test_create_assigns_c_prefixed_id(collections):
    created = _create(collections, USER_A, _collection())
    assert created["id"].startswith("c")
    assert len(created["id"]) > 1
    assert created["name"] == "Test Collection"
    assert created["recipeIds"] == ["r1", "r2", "r3"]


def test_create_ignores_client_supplied_id(collections):
    body = _collection()
    body["id"] = "client-chosen-id"
    created = _create(collections, USER_A, body)
    assert created["id"] != "client-chosen-id"
    assert created["id"].startswith("c")


def test_create_ids_are_unique(collections):
    a = _create(collections, USER_A)
    b = _create(collections, USER_A)
    assert a["id"] != b["id"]


def test_create_without_body_is_400(collections):
    resp = collections.handler(_event("POST", USER_A), None)
    assert resp["statusCode"] == 400


# --- get ------------------------------------------------------------------------------------------
def test_get_returns_created_collection(collections):
    created = _create(collections, USER_A)
    resp = collections.handler(_event("GET", USER_A, collection_id=created["id"]), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == created


def test_get_missing_is_404(collections):
    resp = collections.handler(_event("GET", USER_A, collection_id="cnope"), None)
    assert resp["statusCode"] == 404


# --- list -----------------------------------------------------------------------------------------
def test_list_returns_users_collections(collections):
    _create(collections, USER_A, _collection("A"))
    _create(collections, USER_A, _collection("B"))
    resp = collections.handler(_event("GET", USER_A), None)
    assert resp["statusCode"] == 200
    names = sorted(c["name"] for c in json.loads(resp["body"]))
    assert names == ["A", "B"]


def test_list_empty(collections):
    resp = collections.handler(_event("GET", "ghost"), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == []


# --- update ---------------------------------------------------------------------------------------
def test_update_overwrites_and_keeps_path_id(collections):
    created = _create(collections, USER_A)
    updated_body = _collection("Renamed")
    updated_body["recipeIds"] = ["r9"]
    updated_body["id"] = "should-be-ignored"
    resp = collections.handler(
        _event("PUT", USER_A, collection_id=created["id"], body=updated_body), None
    )
    assert resp["statusCode"] == 200
    out = json.loads(resp["body"])
    assert out["id"] == created["id"]
    assert out["name"] == "Renamed"
    assert out["recipeIds"] == ["r9"]
    # Persisted under the path id.
    again = collections.handler(_event("GET", USER_A, collection_id=created["id"]), None)
    assert json.loads(again["body"])["name"] == "Renamed"


def test_update_without_body_is_400(collections):
    created = _create(collections, USER_A)
    resp = collections.handler(_event("PUT", USER_A, collection_id=created["id"]), None)
    assert resp["statusCode"] == 400


# --- delete ---------------------------------------------------------------------------------------
def test_delete_removes_collection(collections):
    created = _create(collections, USER_A)
    resp = collections.handler(_event("DELETE", USER_A, collection_id=created["id"]), None)
    assert resp["statusCode"] == 204
    gone = collections.handler(_event("GET", USER_A, collection_id=created["id"]), None)
    assert gone["statusCode"] == 404


def test_delete_is_idempotent(collections):
    resp = collections.handler(_event("DELETE", USER_A, collection_id="cnope"), None)
    assert resp["statusCode"] == 204


# --- per-user scoping -----------------------------------------------------------------------------
def test_user_cannot_read_another_users_collection(collections):
    created = _create(collections, USER_A)
    resp = collections.handler(_event("GET", USER_B, collection_id=created["id"]), None)
    assert resp["statusCode"] == 404


def test_user_cannot_see_another_users_collection_in_list(collections):
    _create(collections, USER_A, _collection("A's"))
    resp = collections.handler(_event("GET", USER_B), None)
    assert json.loads(resp["body"]) == []


def test_user_update_does_not_touch_another_users_collection(collections):
    created = _create(collections, USER_A)
    # USER_B "updates" the same id — it must create a *separate* item under USER_B, not overwrite A's.
    collections.handler(
        _event("PUT", USER_B, collection_id=created["id"], body=_collection("B's version")), None
    )
    a_view = collections.handler(_event("GET", USER_A, collection_id=created["id"]), None)
    assert json.loads(a_view["body"])["name"] == "Test Collection"


def test_user_delete_does_not_touch_another_users_collection(collections):
    created = _create(collections, USER_A)
    collections.handler(_event("DELETE", USER_B, collection_id=created["id"]), None)
    a_view = collections.handler(_event("GET", USER_A, collection_id=created["id"]), None)
    assert a_view["statusCode"] == 200


# --- identity resolution --------------------------------------------------------------------------
def test_jwt_claims_take_precedence_over_dev_header(collections):
    created = _create(collections, USER_A)
    # Event carries USER_A in the JWT claims but USER_B in the dev header; JWT must win.
    event = _event("GET", USER_B, collection_id=created["id"])
    event["requestContext"]["authorizer"] = {"jwt": {"claims": {"sub": USER_A}}}
    resp = collections.handler(event, None)
    assert resp["statusCode"] == 200


def test_missing_identity_is_401(collections):
    event = {"requestContext": {"http": {"method": "GET"}}, "headers": {}}
    resp = collections.handler(event, None)
    assert resp["statusCode"] == 401


# --- method routing -------------------------------------------------------------------------------
def test_unsupported_method_is_405(collections):
    resp = collections.handler(_event("PATCH", USER_A, collection_id="c1"), None)
    assert resp["statusCode"] == 405
