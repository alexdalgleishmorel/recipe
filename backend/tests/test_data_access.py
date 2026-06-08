"""Unit tests for the DynamoDB data-access layer (#12), against moto-mocked tables.

Covers put/get/list/delete round-trips per entity, per-user scoping (a Query never crosses userId),
the email and token GSI lookups, float<->Decimal round-tripping, and the model JSON shapes from
frontend/lib/models.
"""

import pytest

USER_A = "user-aaa"
USER_B = "user-bbb"


def _recipe(rid="r1", title="Test Recipe"):
    """A Recipe.toJson()-shaped dict (recipe.dart), incl. nested ingredients + customTags."""
    return {
        "id": rid,
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
        "ingredients": [
            {"amount": "2", "unit": "cups", "name": "flour"},
            {"amount": "1", "unit": "tsp", "name": "salt"},
        ],
        "instructions": ["Mix.", "Bake."],
    }


def _meal_plan(pid="p1"):
    """A MealPlan.toJson()-shaped dict (meal_plan.dart), incl. the nested grid."""
    return {
        "id": pid,
        "name": "Week 1",
        "status": "draft",
        "start": "2026-06-01",
        "end": "2026-06-07",
        "days": ["Mon", "Tue"],
        "dates": ["2026-06-01", "2026-06-02"],
        "meals": ["Dinner"],
        "candidates": ["r1", "r2"],
        "grid": [["r1", None], [None, "r2"]],
    }


# --- per-entity CRUD round-trips ------------------------------------------------------------------
def test_recipe_put_get_round_trip(dal):
    src = _recipe()
    dal.recipes.put(USER_A, src)
    got = dal.recipes.get(USER_A, "r1")
    assert got == src


def test_meal_plan_put_get_round_trip_preserves_grid_and_nulls(dal):
    src = _meal_plan()
    dal.meal_plans.put(USER_A, src)
    got = dal.meal_plans.get(USER_A, "p1")
    assert got == src
    assert got["grid"] == [["r1", None], [None, "r2"]]


def test_collection_round_trip(dal):
    # collection.dart does not exist yet; the DAL is shape-agnostic, so a minimal dict round-trips.
    src = {"id": "c1", "name": "Favorites", "recipeIds": ["r1", "r2"]}
    dal.collections.put(USER_A, src)
    assert dal.collections.get(USER_A, "c1") == src


def test_get_missing_returns_none(dal):
    assert dal.recipes.get(USER_A, "nope") is None


def test_delete_is_idempotent(dal):
    dal.recipes.put(USER_A, _recipe())
    dal.recipes.delete(USER_A, "r1")
    assert dal.recipes.get(USER_A, "r1") is None
    # deleting again must not raise
    dal.recipes.delete(USER_A, "r1")


def test_put_upserts(dal):
    dal.recipes.put(USER_A, _recipe(title="v1"))
    dal.recipes.put(USER_A, _recipe(title="v2"))
    assert dal.recipes.get(USER_A, "r1")["title"] == "v2"


def test_put_without_id_raises(dal):
    with pytest.raises(ValueError):
        dal.recipes.put(USER_A, {"title": "no id"})


# --- list + per-user scoping ---------------------------------------------------------------------
def test_list_returns_all_for_user(dal):
    dal.recipes.put(USER_A, _recipe("r1"))
    dal.recipes.put(USER_A, _recipe("r2"))
    dal.recipes.put(USER_A, _recipe("r3"))
    got = dal.recipes.list(USER_A)
    assert sorted(r["id"] for r in got) == ["r1", "r2", "r3"]


def test_list_is_scoped_to_user(dal):
    dal.recipes.put(USER_A, _recipe("r1"))
    dal.recipes.put(USER_B, _recipe("r2"))
    assert [r["id"] for r in dal.recipes.list(USER_A)] == ["r1"]
    assert [r["id"] for r in dal.recipes.list(USER_B)] == ["r2"]


def test_get_is_scoped_to_user(dal):
    dal.recipes.put(USER_A, _recipe("r1"))
    # USER_B cannot read USER_A's item by id
    assert dal.recipes.get(USER_B, "r1") is None


def test_list_empty(dal):
    assert dal.recipes.list("ghost") == []


# --- GSI lookups ---------------------------------------------------------------------------------
def test_user_get_by_email(dal):
    user = {"id": USER_A, "email": "alex@example.com", "name": "Alex"}
    dal.users.put(USER_A, user)
    assert dal.users.get_by_email("alex@example.com") == user


def test_user_get_by_email_missing(dal):
    assert dal.users.get_by_email("nobody@example.com") is None


def test_share_get_by_token(dal):
    share = {
        "id": "s1",
        "token": "tok-abc123",
        "entityType": "recipe",
        "entityId": "r1",
    }
    dal.shares.put(USER_A, share)
    got = dal.shares.get_by_token("tok-abc123")
    assert got == share


def test_share_get_by_token_missing(dal):
    assert dal.shares.get_by_token("tok-nope") is None


def test_share_list_by_recipient_email(dal):
    # Two shares (from two different sharers) addressed to the same recipient email.
    dal.shares.put("sharer-1", {"id": "s1", "recipientEmail": "bob@example.com", "itemType": "recipe"})
    dal.shares.put("sharer-2", {"id": "s2", "recipientEmail": "bob@example.com", "itemType": "recipe"})
    dal.shares.put("sharer-3", {"id": "s3", "recipientEmail": "carol@example.com", "itemType": "recipe"})
    got = sorted(s["id"] for s in dal.shares.list_by_recipient_email("bob@example.com"))
    assert got == ["s1", "s2"]


def test_share_list_by_recipient_email_empty(dal):
    assert dal.shares.list_by_recipient_email("nobody@example.com") == []


def test_share_without_recipient_email_absent_from_email_index(dal):
    # A link share carries no recipientEmail, so it must not appear in an email query (and the empty
    # value is skipped on write, since DynamoDB rejects an empty indexed key attribute).
    dal.shares.put(USER_A, {"id": "s9", "token": "tok-link", "itemType": "recipe"})
    dal.shares.put("sharer-x", {"id": "s10", "recipientEmail": "bob@example.com", "itemType": "recipe"})
    by_email = [s["id"] for s in dal.shares.list_by_recipient_email("bob@example.com")]
    assert by_email == ["s10"]  # the link share (no recipientEmail) is absent from the index
    assert dal.shares.get_by_token("tok-link")["id"] == "s9"


# --- numeric round-tripping (DynamoDB stores numbers as Decimal) ---------------------------------
def test_float_round_trips_as_float(dal):
    dal.collections.put(USER_A, {"id": "c1", "ratio": 1.5})
    got = dal.collections.get(USER_A, "c1")
    assert got["ratio"] == 1.5
    assert isinstance(got["ratio"], float)


def test_int_round_trips_as_int(dal):
    dal.recipes.put(USER_A, _recipe())
    got = dal.recipes.get(USER_A, "r1")
    assert got["prepTime"] == 10
    assert isinstance(got["prepTime"], int)
