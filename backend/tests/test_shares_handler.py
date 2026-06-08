"""Unit tests for the sharing handler (#18), against moto-mocked DynamoDB (via the `dal` fixture).

Covers fork-share end to end: share by email (resolving an existing recipient + leaving an unknown
email pending), share by link (token + preview), /shares/incoming (matched by both userId and email,
claimed shares excluded), claim forking a recipe and a collection (with rewired recipe ids) under the
claimer with NEW ids, claim using the snapshot even after the source is deleted, idempotent re-claim,
and that a caller can't claim a share not addressed to them. The handler is invoked the way API
Gateway v2 (payload format 2.0) does, with synthetic proxy events.
"""

import json
import os
import sys

import pytest

# Make the shares function module importable without installing it (mirrors test_recipes_handler.py).
# The `common` + `data_access` layers are already on sys.path via conftest's backend/layers insert.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "shares"))

# Sharer + recipients.
SHARER = "user-sharer"
SHARER_EMAIL = "sharer@example.com"
RECIPIENT = "user-recipient"
RECIPIENT_EMAIL = "bob@example.com"
STRANGER = "user-stranger"
STRANGER_EMAIL = "eve@example.com"


def _recipe(rid, title="Carbonara"):
    """A Recipe.toJson()-shaped dict (recipe.dart)."""
    return {
        "id": rid,
        "title": title,
        "cuisine": "Italian",
        "image": "https://img/x.jpg",
        "description": "A test recipe.",
        "prepTime": 10,
        "cookTime": 20,
        "servings": 4,
        "tags": ["dinner"],
        "dietary": [],
        "author": "Sharer",
        "customTags": [],
        "ingredients": [{"amount": "2", "unit": "cups", "name": "flour"}],
        "instructions": ["Mix.", "Cook."],
    }


def _collection(cid, recipe_ids, name="Weeknight"):
    return {"id": cid, "name": name, "description": "Go-to dinners.", "recipeIds": recipe_ids}


def _event(method, user_id=None, email=None, path=None, body=None):
    """Build a synthetic API Gateway v2 (payload 2.0) proxy event for the shares handler.

    `path` is a dict of path parameters (e.g. {"token": "..."} or {"idOrToken": "..."}).
    """
    headers = {}
    if user_id is not None:
        headers["x-user-id"] = user_id
    if email is not None:
        headers["x-user-email"] = email
    event = {"requestContext": {"http": {"method": method}}, "headers": headers}
    if path is not None:
        event["pathParameters"] = path
    if body is not None:
        event["body"] = json.dumps(body)
    return event


@pytest.fixture
def shares(dal):
    """Import the shares handler after the moto mock + DAL are active."""
    import shares as module

    return module


@pytest.fixture
def seeded(dal):
    """Seed the sharer's library: a recipe profile for the recipient + a recipe and a collection."""
    # The recipient already has a profile, so an email share resolves to their userId.
    dal.users.put(RECIPIENT, {"id": RECIPIENT, "email": RECIPIENT_EMAIL, "displayName": "Bob"})
    dal.recipes.put(SHARER, _recipe("r1", "Carbonara"))
    dal.recipes.put(SHARER, _recipe("r2", "Tiramisu"))
    dal.collections.put(SHARER, _collection("c1", ["r1", "r2"]))
    return dal


# --- POST /shares: by email -----------------------------------------------------------------------
def test_share_recipe_by_email_resolves_existing_recipient(shares, seeded):
    resp = shares.handler(
        _event(
            "POST",
            SHARER,
            email=SHARER_EMAIL,
            body={"itemType": "recipe", "itemId": "r1", "target": {"email": RECIPIENT_EMAIL}},
        ),
        None,
    )
    assert resp["statusCode"] == 201
    share = json.loads(resp["body"])
    assert share["recipientEmail"] == RECIPIENT_EMAIL
    assert share["recipientUserId"] == RECIPIENT
    assert share["claimed"] is False
    # Snapshot captured the live recipe.
    assert share["snapshot"]["recipe"]["title"] == "Carbonara"
    assert share["snapshot"]["title"] == "Carbonara"
    assert "token" not in share


def test_share_by_email_lowercases_recipient(shares, seeded):
    resp = shares.handler(
        _event(
            "POST",
            SHARER,
            body={"itemType": "recipe", "itemId": "r1", "target": {"email": "BOB@Example.COM"}},
        ),
        None,
    )
    share = json.loads(resp["body"])
    assert share["recipientEmail"] == "bob@example.com"
    assert share["recipientUserId"] == RECIPIENT


def test_share_by_email_unknown_recipient_is_pending(shares, seeded):
    resp = shares.handler(
        _event(
            "POST",
            SHARER,
            body={"itemType": "recipe", "itemId": "r1", "target": {"email": "ghost@example.com"}},
        ),
        None,
    )
    share = json.loads(resp["body"])
    assert share["recipientEmail"] == "ghost@example.com"
    # No profile for that email yet -> pending, no resolved userId.
    assert "recipientUserId" not in share


def test_share_missing_item_is_404(shares, seeded):
    resp = shares.handler(
        _event(
            "POST",
            SHARER,
            body={"itemType": "recipe", "itemId": "rnope", "target": {"email": RECIPIENT_EMAIL}},
        ),
        None,
    )
    assert resp["statusCode"] == 404


def test_share_bad_item_type_is_400(shares, seeded):
    resp = shares.handler(
        _event("POST", SHARER, body={"itemType": "plan", "itemId": "r1", "target": {"link": True}}),
        None,
    )
    assert resp["statusCode"] == 400


def test_share_bad_target_is_400(shares, seeded):
    resp = shares.handler(
        _event("POST", SHARER, body={"itemType": "recipe", "itemId": "r1", "target": {}}), None
    )
    assert resp["statusCode"] == 400


# --- POST /shares: by link ------------------------------------------------------------------------
def test_share_by_link_generates_token(shares, seeded):
    resp = shares.handler(
        _event("POST", SHARER, body={"itemType": "recipe", "itemId": "r1", "target": {"link": True}}),
        None,
    )
    assert resp["statusCode"] == 201
    share = json.loads(resp["body"])
    assert share["token"]
    assert "recipientEmail" not in share
    assert "recipientUserId" not in share


def test_link_preview_returns_display_metadata(shares, seeded):
    created = json.loads(
        shares.handler(
            _event(
                "POST", SHARER, body={"itemType": "recipe", "itemId": "r1", "target": {"link": True}}
            ),
            None,
        )["body"]
    )
    token = created["token"]
    # Preview by anyone (token is the credential).
    resp = shares.handler(_event("GET", STRANGER, email=STRANGER_EMAIL, path={"token": token}), None)
    assert resp["statusCode"] == 200
    preview = json.loads(resp["body"])
    assert preview["title"] == "Carbonara"
    assert preview["itemType"] == "recipe"
    assert preview["token"] == token


def test_link_preview_unknown_token_is_404(shares, seeded):
    resp = shares.handler(_event("GET", STRANGER, path={"token": "nope"}), None)
    assert resp["statusCode"] == 404


# --- GET /shares/incoming -------------------------------------------------------------------------
def _share_by_email(shares, item_id="r1", item_type="recipe", recipient=RECIPIENT_EMAIL):
    return json.loads(
        shares.handler(
            _event(
                "POST",
                SHARER,
                email=SHARER_EMAIL,
                body={"itemType": item_type, "itemId": item_id, "target": {"email": recipient}},
            ),
            None,
        )["body"]
    )


def test_incoming_lists_by_resolved_userid(shares, seeded):
    _share_by_email(shares)
    resp = shares.handler(
        _event("GET", RECIPIENT, email=RECIPIENT_EMAIL, path={}), None
    )
    assert resp["statusCode"] == 200
    incoming = json.loads(resp["body"])
    assert len(incoming) == 1
    assert incoming[0]["recipientUserId"] == RECIPIENT


def test_incoming_lists_by_email_when_pending(shares, seeded):
    # Share addressed to an email with no profile yet; recipient signs in later as a new userId.
    _share_by_email(shares, recipient="late@example.com")
    new_user = "user-late"
    resp = shares.handler(_event("GET", new_user, email="late@example.com", path={}), None)
    incoming = json.loads(resp["body"])
    assert len(incoming) == 1
    assert incoming[0]["recipientEmail"] == "late@example.com"


def test_incoming_excludes_other_users(shares, seeded):
    _share_by_email(shares)
    resp = shares.handler(_event("GET", STRANGER, email=STRANGER_EMAIL, path={}), None)
    assert json.loads(resp["body"]) == []


def test_incoming_excludes_claimed(shares, seeded):
    share = _share_by_email(shares)
    # Claim it, then it must not reappear in incoming.
    shares.handler(_event("POST", RECIPIENT, email=RECIPIENT_EMAIL, path={"idOrToken": share["id"]}), None)
    resp = shares.handler(_event("GET", RECIPIENT, email=RECIPIENT_EMAIL, path={}), None)
    assert json.loads(resp["body"]) == []


# --- POST /shares/{idOrToken}/claim: recipe fork --------------------------------------------------
def test_claim_email_share_forks_recipe_with_new_id(shares, seeded):
    share = _share_by_email(shares)
    resp = shares.handler(
        _event("POST", RECIPIENT, email=RECIPIENT_EMAIL, path={"idOrToken": share["id"]}), None
    )
    assert resp["statusCode"] == 200
    result = json.loads(resp["body"])
    new_id = result["recipeId"]
    assert new_id != "r1"
    assert new_id.startswith("r")
    # The copy lives under the claimer with the snapshot's content.
    copy = seeded.recipes.get(RECIPIENT, new_id)
    assert copy["title"] == "Carbonara"
    assert copy["id"] == new_id
    # The sharer's original is untouched.
    assert seeded.recipes.get(SHARER, "r1")["id"] == "r1"
    # The claimer didn't get a row under the sharer's id.
    assert seeded.recipes.get(RECIPIENT, "r1") is None


def test_claim_link_share_by_token_forks_recipe(shares, seeded):
    created = json.loads(
        shares.handler(
            _event(
                "POST", SHARER, body={"itemType": "recipe", "itemId": "r1", "target": {"link": True}}
            ),
            None,
        )["body"]
    )
    token = created["token"]
    resp = shares.handler(
        _event("POST", STRANGER, email=STRANGER_EMAIL, path={"idOrToken": token}), None
    )
    assert resp["statusCode"] == 200
    new_id = json.loads(resp["body"])["recipeId"]
    assert seeded.recipes.get(STRANGER, new_id)["title"] == "Carbonara"


# --- claim: collection fork (rewires recipe ids) --------------------------------------------------
def test_claim_collection_forks_collection_and_recipes_with_rewired_ids(shares, seeded):
    share = _share_by_email(shares, item_id="c1", item_type="collection")
    resp = shares.handler(
        _event("POST", RECIPIENT, email=RECIPIENT_EMAIL, path={"idOrToken": share["id"]}), None
    )
    assert resp["statusCode"] == 200
    result = json.loads(resp["body"])
    new_cid = result["collectionId"]
    new_recipe_ids = result["recipeIds"]
    assert new_cid != "c1" and new_cid.startswith("c")
    assert len(new_recipe_ids) == 2
    assert set(new_recipe_ids).isdisjoint({"r1", "r2"})
    # The forked collection points at the forked recipes (rewired), not the originals.
    forked = seeded.collections.get(RECIPIENT, new_cid)
    assert forked["recipeIds"] == new_recipe_ids
    titles = sorted(seeded.recipes.get(RECIPIENT, rid)["title"] for rid in new_recipe_ids)
    assert titles == ["Carbonara", "Tiramisu"]


# --- claim: snapshot is authoritative -------------------------------------------------------------
def test_claim_uses_snapshot_after_source_deleted(shares, seeded):
    share = _share_by_email(shares)
    # Owner deletes the original recipe before the recipient claims.
    seeded.recipes.delete(SHARER, "r1")
    resp = shares.handler(
        _event("POST", RECIPIENT, email=RECIPIENT_EMAIL, path={"idOrToken": share["id"]}), None
    )
    assert resp["statusCode"] == 200
    new_id = json.loads(resp["body"])["recipeId"]
    assert seeded.recipes.get(RECIPIENT, new_id)["title"] == "Carbonara"


# --- claim: idempotency ---------------------------------------------------------------------------
def test_reclaim_is_idempotent(shares, seeded):
    share = _share_by_email(shares)
    first = json.loads(
        shares.handler(
            _event("POST", RECIPIENT, email=RECIPIENT_EMAIL, path={"idOrToken": share["id"]}), None
        )["body"]
    )
    resp = shares.handler(
        _event("POST", RECIPIENT, email=RECIPIENT_EMAIL, path={"idOrToken": share["id"]}), None
    )
    assert resp["statusCode"] == 200
    again = json.loads(resp["body"])
    assert again == first
    # No duplicate copy created on re-claim.
    assert len(seeded.recipes.list(RECIPIENT)) == 1


# --- claim: not addressed to caller ---------------------------------------------------------------
def test_cannot_claim_email_share_not_addressed_to_caller(shares, seeded):
    share = _share_by_email(shares)
    # A stranger (different email, no token) can't claim a share addressed to RECIPIENT_EMAIL.
    resp = shares.handler(
        _event("POST", STRANGER, email=STRANGER_EMAIL, path={"idOrToken": share["id"]}), None
    )
    assert resp["statusCode"] == 404
    # Nothing forked for the stranger.
    assert seeded.recipes.list(STRANGER) == []


def test_cannot_claim_link_share_without_the_token(shares, seeded):
    created = json.loads(
        shares.handler(
            _event(
                "POST", SHARER, body={"itemType": "recipe", "itemId": "r1", "target": {"link": True}}
            ),
            None,
        )["body"]
    )
    # Using the share id (not the token) on a link share is not a valid claim credential.
    resp = shares.handler(
        _event("POST", STRANGER, email=STRANGER_EMAIL, path={"idOrToken": created["id"]}), None
    )
    assert resp["statusCode"] == 404


# --- method routing -------------------------------------------------------------------------------
def test_missing_identity_on_create_is_401(shares, seeded):
    resp = shares.handler(
        _event("POST", body={"itemType": "recipe", "itemId": "r1", "target": {"link": True}}), None
    )
    assert resp["statusCode"] == 401


def test_unsupported_method_is_405(shares, seeded):
    resp = shares.handler(_event("DELETE", SHARER, path={"token": "x"}), None)
    assert resp["statusCode"] == 405
