"""Unit tests for the plans CRUD handler (#15), against moto-mocked DynamoDB (via the `dal` fixture).

Covers each route (list/create/get/update/delete), server-assigned ids, and per-user scoping (a user
can neither read, update, nor delete another user's plan). The handler is invoked the way API
Gateway v2 (payload format 2.0) does, with synthetic proxy events. Mirrors test_recipes_handler.py.
"""

import json
import os
import sys

import pytest

# Make the plans function module importable without installing it (mirrors test_recipes_handler.py).
# The `common` + `data_access` layers are already on sys.path via conftest's backend/layers insert.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "plans"))

USER_A = "user-aaa"
USER_B = "user-bbb"


def _plan(name="Test Plan"):
    """A MealPlan.toJson()-shaped dict (meal_plan.dart) without an id (the server assigns it)."""
    return {
        "name": name,
        "status": "draft",
        "start": "2026-06-08",
        "end": "2026-06-14",
        "days": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
        "dates": [
            "2026-06-08",
            "2026-06-09",
            "2026-06-10",
            "2026-06-11",
            "2026-06-12",
            "2026-06-13",
            "2026-06-14",
        ],
        "meals": ["Breakfast", "Lunch", "Dinner"],
        "candidates": ["r1", "r2"],
        "grid": [
            ["r1", None, "r2"],
            [None, None, None],
            ["r2", "r1", None],
            [None, None, None],
            [None, None, None],
            [None, None, None],
            [None, None, None],
        ],
    }


def _event(method, user_id, plan_id=None, body=None):
    """Build a synthetic API Gateway v2 (payload 2.0) proxy event for the plans handler."""
    event = {
        "requestContext": {"http": {"method": method}},
        "headers": {"x-user-id": user_id},
    }
    if plan_id is not None:
        event["pathParameters"] = {"id": plan_id}
    if body is not None:
        event["body"] = json.dumps(body)
    return event


@pytest.fixture
def plans(dal):
    """Import the plans handler after the moto mock + DAL are active."""
    import plans as module

    return module


def _create(plans, user_id, body=None):
    resp = plans.handler(_event("POST", user_id, body=body or _plan()), None)
    assert resp["statusCode"] == 201
    return json.loads(resp["body"])


# --- create + server-assigned ids -----------------------------------------------------------------
def test_create_assigns_p_prefixed_id(plans):
    created = _create(plans, USER_A, _plan())
    assert created["id"].startswith("p")
    assert len(created["id"]) > 1
    assert created["name"] == "Test Plan"


def test_create_ignores_client_supplied_id(plans):
    body = _plan()
    body["id"] = "client-chosen-id"
    created = _create(plans, USER_A, body)
    assert created["id"] != "client-chosen-id"
    assert created["id"].startswith("p")


def test_create_ids_are_unique(plans):
    a = _create(plans, USER_A)
    b = _create(plans, USER_A)
    assert a["id"] != b["id"]


def test_create_without_body_is_400(plans):
    resp = plans.handler(_event("POST", USER_A), None)
    assert resp["statusCode"] == 400


# --- get ------------------------------------------------------------------------------------------
def test_get_returns_created_plan(plans):
    created = _create(plans, USER_A)
    resp = plans.handler(_event("GET", USER_A, plan_id=created["id"]), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == created


def test_get_missing_is_404(plans):
    resp = plans.handler(_event("GET", USER_A, plan_id="pnope"), None)
    assert resp["statusCode"] == 404


# --- list -----------------------------------------------------------------------------------------
def test_list_returns_users_plans(plans):
    _create(plans, USER_A, _plan("A"))
    _create(plans, USER_A, _plan("B"))
    resp = plans.handler(_event("GET", USER_A), None)
    assert resp["statusCode"] == 200
    names = sorted(p["name"] for p in json.loads(resp["body"]))
    assert names == ["A", "B"]


def test_list_empty(plans):
    resp = plans.handler(_event("GET", "ghost"), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == []


# --- update ---------------------------------------------------------------------------------------
def test_update_overwrites_and_keeps_path_id(plans):
    created = _create(plans, USER_A)
    updated_body = _plan("Renamed")
    updated_body["id"] = "should-be-ignored"
    resp = plans.handler(_event("PUT", USER_A, plan_id=created["id"], body=updated_body), None)
    assert resp["statusCode"] == 200
    out = json.loads(resp["body"])
    assert out["id"] == created["id"]
    assert out["name"] == "Renamed"
    # Persisted under the path id.
    again = plans.handler(_event("GET", USER_A, plan_id=created["id"]), None)
    assert json.loads(again["body"])["name"] == "Renamed"


def test_update_without_body_is_400(plans):
    created = _create(plans, USER_A)
    resp = plans.handler(_event("PUT", USER_A, plan_id=created["id"]), None)
    assert resp["statusCode"] == 400


# --- delete ---------------------------------------------------------------------------------------
def test_delete_removes_plan(plans):
    created = _create(plans, USER_A)
    resp = plans.handler(_event("DELETE", USER_A, plan_id=created["id"]), None)
    assert resp["statusCode"] == 204
    gone = plans.handler(_event("GET", USER_A, plan_id=created["id"]), None)
    assert gone["statusCode"] == 404


def test_delete_is_idempotent(plans):
    resp = plans.handler(_event("DELETE", USER_A, plan_id="pnope"), None)
    assert resp["statusCode"] == 204


# --- per-user scoping -----------------------------------------------------------------------------
def test_user_cannot_read_another_users_plan(plans):
    created = _create(plans, USER_A)
    resp = plans.handler(_event("GET", USER_B, plan_id=created["id"]), None)
    assert resp["statusCode"] == 404


def test_user_cannot_see_another_users_plan_in_list(plans):
    _create(plans, USER_A, _plan("A's"))
    resp = plans.handler(_event("GET", USER_B), None)
    assert json.loads(resp["body"]) == []


def test_user_update_does_not_touch_another_users_plan(plans):
    created = _create(plans, USER_A)
    # USER_B "updates" the same id — it must create a *separate* item under USER_B, not overwrite A's.
    plans.handler(_event("PUT", USER_B, plan_id=created["id"], body=_plan("B's version")), None)
    a_view = plans.handler(_event("GET", USER_A, plan_id=created["id"]), None)
    assert json.loads(a_view["body"])["name"] == "Test Plan"


def test_user_delete_does_not_touch_another_users_plan(plans):
    created = _create(plans, USER_A)
    plans.handler(_event("DELETE", USER_B, plan_id=created["id"]), None)
    a_view = plans.handler(_event("GET", USER_A, plan_id=created["id"]), None)
    assert a_view["statusCode"] == 200


# --- identity resolution --------------------------------------------------------------------------
def test_jwt_claims_take_precedence_over_dev_header(plans):
    created = _create(plans, USER_A)
    # Event carries USER_A in the JWT claims but USER_B in the dev header; JWT must win.
    event = _event("GET", USER_B, plan_id=created["id"])
    event["requestContext"]["authorizer"] = {"jwt": {"claims": {"sub": USER_A}}}
    resp = plans.handler(event, None)
    assert resp["statusCode"] == 200


def test_missing_identity_is_401(plans):
    event = {"requestContext": {"http": {"method": "GET"}}, "headers": {}}
    resp = plans.handler(event, None)
    assert resp["statusCode"] == 401


# --- method routing -------------------------------------------------------------------------------
def test_unsupported_method_is_405(plans):
    resp = plans.handler(_event("PATCH", USER_A, plan_id="p1"), None)
    assert resp["statusCode"] == 405
