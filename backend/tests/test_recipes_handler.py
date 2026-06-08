"""Unit tests for the recipes CRUD handler (#14), against moto-mocked DynamoDB (via the `dal` fixture).

Covers each route (list/create/get/update/delete), server-assigned ids, and per-user scoping (a user
can neither read, update, nor delete another user's recipe). The handler is invoked the way API
Gateway v2 (payload format 2.0) does, with synthetic proxy events.
"""

import json
import os
import sys

import pytest

# Make the recipes function module importable without installing it (mirrors test_hello.py). The
# `common` + `data_access` layers are already on sys.path via conftest's backend/layers insert.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "recipes"))

USER_A = "user-aaa"
USER_B = "user-bbb"


def _recipe(title="Test Recipe"):
    """A Recipe.toJson()-shaped dict (recipe.dart) without an id (the server assigns it)."""
    return {
        "title": title,
        "cuisine": "Italian",
        "image": "https://img/x.jpg",
        "description": "A test recipe.",
        "prepTime": 10,
        "cookTime": 20,
        "servings": 4,
        "tags": ["dinner", "quick"],
        "dietary": ["vegetarian"],
        "author": "Me",
        "customTags": [{"key": "spice", "value": "mild"}],
        "ingredients": [{"amount": "2", "unit": "cups", "name": "flour"}],
        "instructions": ["Mix.", "Bake."],
    }


def _event(method, user_id, recipe_id=None, body=None):
    """Build a synthetic API Gateway v2 (payload 2.0) proxy event for the recipes handler."""
    event = {
        "requestContext": {"http": {"method": method}},
        "headers": {"x-user-id": user_id},
    }
    if recipe_id is not None:
        event["pathParameters"] = {"id": recipe_id}
    if body is not None:
        event["body"] = json.dumps(body)
    return event


@pytest.fixture
def recipes(dal):
    """Import the recipes handler after the moto mock + DAL are active."""
    import recipes as module

    return module


def _create(recipes, user_id, body=None):
    resp = recipes.handler(_event("POST", user_id, body=body or _recipe()), None)
    assert resp["statusCode"] == 201
    return json.loads(resp["body"])


# --- create + server-assigned ids -----------------------------------------------------------------
def test_create_assigns_r_prefixed_id(recipes):
    created = _create(recipes, USER_A, _recipe())
    assert created["id"].startswith("r")
    assert len(created["id"]) > 1
    assert created["title"] == "Test Recipe"


def test_create_ignores_client_supplied_id(recipes):
    body = _recipe()
    body["id"] = "client-chosen-id"
    created = _create(recipes, USER_A, body)
    assert created["id"] != "client-chosen-id"
    assert created["id"].startswith("r")


def test_create_ids_are_unique(recipes):
    a = _create(recipes, USER_A)
    b = _create(recipes, USER_A)
    assert a["id"] != b["id"]


def test_create_without_body_is_400(recipes):
    resp = recipes.handler(_event("POST", USER_A), None)
    assert resp["statusCode"] == 400


# --- get ------------------------------------------------------------------------------------------
def test_get_returns_created_recipe(recipes):
    created = _create(recipes, USER_A)
    resp = recipes.handler(_event("GET", USER_A, recipe_id=created["id"]), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == created


def test_get_missing_is_404(recipes):
    resp = recipes.handler(_event("GET", USER_A, recipe_id="rnope"), None)
    assert resp["statusCode"] == 404


# --- list -----------------------------------------------------------------------------------------
def test_list_returns_users_recipes(recipes):
    _create(recipes, USER_A, _recipe("A"))
    _create(recipes, USER_A, _recipe("B"))
    resp = recipes.handler(_event("GET", USER_A), None)
    assert resp["statusCode"] == 200
    titles = sorted(r["title"] for r in json.loads(resp["body"]))
    assert titles == ["A", "B"]


def test_list_empty(recipes):
    resp = recipes.handler(_event("GET", "ghost"), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == []


# --- update ---------------------------------------------------------------------------------------
def test_update_overwrites_and_keeps_path_id(recipes):
    created = _create(recipes, USER_A)
    updated_body = _recipe("Renamed")
    updated_body["id"] = "should-be-ignored"
    resp = recipes.handler(_event("PUT", USER_A, recipe_id=created["id"], body=updated_body), None)
    assert resp["statusCode"] == 200
    out = json.loads(resp["body"])
    assert out["id"] == created["id"]
    assert out["title"] == "Renamed"
    # Persisted under the path id.
    again = recipes.handler(_event("GET", USER_A, recipe_id=created["id"]), None)
    assert json.loads(again["body"])["title"] == "Renamed"


def test_update_without_body_is_400(recipes):
    created = _create(recipes, USER_A)
    resp = recipes.handler(_event("PUT", USER_A, recipe_id=created["id"]), None)
    assert resp["statusCode"] == 400


# --- delete ---------------------------------------------------------------------------------------
def test_delete_removes_recipe(recipes):
    created = _create(recipes, USER_A)
    resp = recipes.handler(_event("DELETE", USER_A, recipe_id=created["id"]), None)
    assert resp["statusCode"] == 204
    gone = recipes.handler(_event("GET", USER_A, recipe_id=created["id"]), None)
    assert gone["statusCode"] == 404


def test_delete_is_idempotent(recipes):
    resp = recipes.handler(_event("DELETE", USER_A, recipe_id="rnope"), None)
    assert resp["statusCode"] == 204


# --- per-user scoping -----------------------------------------------------------------------------
def test_user_cannot_read_another_users_recipe(recipes):
    created = _create(recipes, USER_A)
    resp = recipes.handler(_event("GET", USER_B, recipe_id=created["id"]), None)
    assert resp["statusCode"] == 404


def test_user_cannot_see_another_users_recipe_in_list(recipes):
    _create(recipes, USER_A, _recipe("A's"))
    resp = recipes.handler(_event("GET", USER_B), None)
    assert json.loads(resp["body"]) == []


def test_user_update_does_not_touch_another_users_recipe(recipes):
    created = _create(recipes, USER_A)
    # USER_B "updates" the same id — it must create a *separate* item under USER_B, not overwrite A's.
    recipes.handler(_event("PUT", USER_B, recipe_id=created["id"], body=_recipe("B's version")), None)
    a_view = recipes.handler(_event("GET", USER_A, recipe_id=created["id"]), None)
    assert json.loads(a_view["body"])["title"] == "Test Recipe"


def test_user_delete_does_not_touch_another_users_recipe(recipes):
    created = _create(recipes, USER_A)
    recipes.handler(_event("DELETE", USER_B, recipe_id=created["id"]), None)
    a_view = recipes.handler(_event("GET", USER_A, recipe_id=created["id"]), None)
    assert a_view["statusCode"] == 200


# --- identity resolution --------------------------------------------------------------------------
def test_jwt_claims_take_precedence_over_dev_header(recipes):
    created = _create(recipes, USER_A)
    # Event carries USER_A in the JWT claims but USER_B in the dev header; JWT must win.
    event = _event("GET", USER_B, recipe_id=created["id"])
    event["requestContext"]["authorizer"] = {"jwt": {"claims": {"sub": USER_A}}}
    resp = recipes.handler(event, None)
    assert resp["statusCode"] == 200


def test_missing_identity_is_401(recipes):
    event = {"requestContext": {"http": {"method": "GET"}}, "headers": {}}
    resp = recipes.handler(event, None)
    assert resp["statusCode"] == 401


# --- method routing -------------------------------------------------------------------------------
def test_unsupported_method_is_405(recipes):
    resp = recipes.handler(_event("PATCH", USER_A, recipe_id="r1"), None)
    assert resp["statusCode"] == 405
