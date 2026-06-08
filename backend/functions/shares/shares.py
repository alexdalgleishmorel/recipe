"""Sharing handler (#18) — fork-share (editable COPY) of recipes and collections.

Sharing always produces an independent COPY of the item in the recipient's library on claim, by one of
two targeting modes: by email (resolve the recipient via the users email GSI; pending on the email if
they haven't signed in yet) or by an unguessable shareable link token. Because the source owner may
edit or delete the original before it's claimed, the shared item(s) are SNAPSHOTTED into the Share
record at share time — claim deep-copies from that snapshot, never the live source.

Backs ``SharingRepository`` (frontend/lib/services/repositories.dart). One Lambda dispatches all routes
(scoped to the caller's userId via ``common.get_user_id``, except link preview which is by token):

    POST /shares                 -> create a share (snapshot the item; email or link target)
    GET  /shares/incoming        -> shares targeted at the caller (by userId or by email), unclaimed
    GET  /shares/{token}         -> preview a link share (the snapshot's display metadata)
    POST /shares/{idOrToken}/claim -> deep-copy the snapshot into the caller's library with NEW ids,
                                      then mark the share claimed (idempotent)

The Share record is stored under the *sharer's* userId (PK), SK = a server-assigned ``s<uuid>`` id:

    {
      "id", "itemType": "recipe"|"collection", "itemId",
      "token"?,              # link shares only (GSI key)
      "recipientEmail"?,     # email shares only, lowercased (GSI key)
      "recipientUserId"?,    # resolved if the recipient already has a profile
      "fromEmail",           # the sharer's email (best-effort), for "Shared with me" display
      "sharedAt", "claimed", "claimedAt"?, "claimedBy"?,
      "snapshot": {          # frozen copy taken at share time
        "title": "...",                 # display metadata
        "recipe": {...}                 # itemType == recipe
        "collection": {...},            # itemType == collection
        "recipes": [{...}, ...]         #   + its member recipes
      }
    }
"""

from __future__ import annotations

import datetime
import secrets
import uuid
from typing import Any, Optional

from common import api, get_user_email, get_user_id
from data_access import collections, recipes, shares, users

SHARE_ID_PREFIX = "s"
RECIPE_ID_PREFIX = "r"
COLLECTION_ID_PREFIX = "c"

VALID_ITEM_TYPES = ("recipe", "collection")


def _new_id(prefix: str) -> str:
    """A server-assigned id: ``prefix`` + a uuid4 hex (no dashes). Matches the other handlers."""
    return f"{prefix}{uuid.uuid4().hex}"


def _new_token() -> str:
    """An unguessable, URL-safe share-link token."""
    return secrets.token_urlsafe(24)


def _now() -> str:
    """Current UTC time as an ISO-8601 string (matches the frontend's ``sharedAt`` parsing)."""
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _norm_email(value: Optional[str]) -> Optional[str]:
    """Lower-case + strip an email; ``None`` for empty/missing."""
    if not value:
        return None
    cleaned = value.strip().lower()
    return cleaned or None


# --- snapshotting ---------------------------------------------------------------------------------
def _snapshot_recipe(user_id: str, recipe_id: str) -> Optional[dict]:
    """Freeze a recipe's current JSON into a snapshot, or ``None`` if the caller has no such recipe."""
    recipe = recipes.get(user_id, recipe_id)
    if recipe is None:
        return None
    return {"title": recipe.get("title", ""), "recipe": recipe}


def _snapshot_collection(user_id: str, collection_id: str) -> Optional[dict]:
    """Freeze a collection + each of its member recipes, or ``None`` if the collection is absent.

    Member recipes that no longer exist are simply skipped (the fork copies what's there at share time).
    """
    collection = collections.get(user_id, collection_id)
    if collection is None:
        return None
    member_recipes = []
    for rid in collection.get("recipeIds", []) or []:
        recipe = recipes.get(user_id, rid)
        if recipe is not None:
            member_recipes.append(recipe)
    return {
        "title": collection.get("name", ""),
        "collection": collection,
        "recipes": member_recipes,
    }


# --- POST /shares ---------------------------------------------------------------------------------
def _create(user_id: str, event: dict) -> dict:
    body = api.body(event)
    item_type = body.get("itemType")
    item_id = body.get("itemId")
    target = body.get("target") or {}

    if item_type not in VALID_ITEM_TYPES:
        return api.bad_request("itemType must be 'recipe' or 'collection'")
    if not item_id:
        return api.bad_request("itemId is required")
    if not isinstance(target, dict):
        return api.bad_request("target must be an object")

    snapshot = (
        _snapshot_recipe(user_id, item_id)
        if item_type == "recipe"
        else _snapshot_collection(user_id, item_id)
    )
    if snapshot is None:
        return api.not_found(f"{item_type} '{item_id}' not found")

    share: dict[str, Any] = {
        "id": _new_id(SHARE_ID_PREFIX),
        "itemType": item_type,
        "itemId": item_id,
        # The row's DynamoDB PK is the sharer's userId, but the doc doesn't carry the PK; stash it so a
        # claim (which finds the row via a GSI, partition unknown) can rewrite the *original* row.
        "ownerUserId": user_id,
        "fromEmail": get_user_email(event) or "",
        "sharedAt": _now(),
        "claimed": False,
        "snapshot": snapshot,
    }

    target_email = _norm_email(target.get("email"))
    if target_email:
        share["recipientEmail"] = target_email
        # Resolve to an existing recipient if they already have a profile; otherwise the share stays
        # pending on the email and surfaces once they sign in (matched by email in /shares/incoming).
        recipient = users.get_by_email(target_email)
        if recipient and recipient.get("id"):
            share["recipientUserId"] = recipient["id"]
    elif target.get("link"):
        share["token"] = _new_token()
    else:
        return api.bad_request("target must be {email: ...} or {link: true}")

    saved = shares.put(user_id, share)
    return api.created(saved)


# --- GET /shares/incoming -------------------------------------------------------------------------
def _incoming(user_id: str, event: dict) -> dict:
    """Shares targeted at the caller: recipientUserId == caller, OR recipientEmail == caller's email.

    Already-claimed shares are excluded. De-duplicated by share id (a share can match on both keys).
    """
    email = _norm_email(get_user_email(event))
    if not email:
        return api.ok([])

    # Every email share carries recipientEmail (and recipientUserId too, once resolved), and email
    # shares are the only ones with a recipient — so the email GSI surfaces both the pending shares
    # and the ones already resolved to this caller's userId. Filter to this caller and drop claimed.
    result = [
        s
        for s in shares.list_by_recipient_email(email)
        if not s.get("claimed")
        and (s.get("recipientUserId") == user_id or _norm_email(s.get("recipientEmail")) == email)
    ]
    result.sort(key=lambda s: s.get("sharedAt", ""), reverse=True)
    return api.ok(result)


# --- GET /shares/{token} (preview) ----------------------------------------------------------------
def _preview(token: str) -> dict:
    """Return a link share's display metadata so the recipient can see what they'd claim."""
    share = shares.get_by_token(token)
    if share is None:
        return api.not_found("share link not found")
    snapshot = share.get("snapshot") or {}
    return api.ok(
        {
            "id": share["id"],
            "token": share.get("token"),
            "itemType": share.get("itemType"),
            "title": snapshot.get("title", ""),
            "fromEmail": share.get("fromEmail", ""),
            "sharedAt": share.get("sharedAt"),
            "claimed": bool(share.get("claimed")),
        }
    )


# --- POST /shares/{idOrToken}/claim ---------------------------------------------------------------
def _resolve_claimable(user_id: str, email: Optional[str], id_or_token: str) -> Optional[dict]:
    """Find a share the caller is entitled to claim by id-or-token; ``None`` if not addressed to them.

    A caller may claim a share when either:
      * it's a link share whose token they hold (``id_or_token`` == the token), or
      * it's addressed to them by email/userId and ``id_or_token`` == the share id.

    The sharer's own userId is unknown to the recipient, so an email/userId share is located via the
    email GSI; a link share is located via the token GSI.
    """
    # Link path: the token itself is the bearer credential.
    by_token = shares.get_by_token(id_or_token)
    if by_token is not None and by_token.get("token") == id_or_token:
        return by_token

    # Email path: only shares addressed to this caller's email (or resolved userId) are claimable.
    if email:
        for share in shares.list_by_recipient_email(email):
            if share.get("id") == id_or_token and (
                share.get("recipientUserId") == user_id
                or _norm_email(share.get("recipientEmail")) == email
            ):
                return share
    return None


def _fork_recipe(user_id: str, recipe_doc: dict) -> str:
    """Deep-copy a snapshotted recipe under ``user_id`` with a NEW id. Returns the new id."""
    copy = dict(recipe_doc)
    copy["id"] = _new_id(RECIPE_ID_PREFIX)
    recipes.put(user_id, copy)
    return copy["id"]


def _claim_into_library(user_id: str, share: dict) -> dict:
    """Deep-copy the share's snapshot into ``user_id``'s library with fresh ids. Returns the new ids."""
    snapshot = share.get("snapshot") or {}
    if share.get("itemType") == "recipe":
        recipe_doc = snapshot.get("recipe") or {}
        new_id = _fork_recipe(user_id, recipe_doc)
        return {"itemType": "recipe", "recipeId": new_id}

    # Collection: fork each member recipe first, then the collection rewired to the new recipe ids.
    new_recipe_ids = [_fork_recipe(user_id, r) for r in (snapshot.get("recipes") or [])]
    collection_copy = dict(snapshot.get("collection") or {})
    collection_copy["id"] = _new_id(COLLECTION_ID_PREFIX)
    collection_copy["recipeIds"] = new_recipe_ids
    collections.put(user_id, collection_copy)
    return {
        "itemType": "collection",
        "collectionId": collection_copy["id"],
        "recipeIds": new_recipe_ids,
    }


def _claim(user_id: str, event: dict, id_or_token: str) -> dict:
    email = _norm_email(get_user_email(event))
    share = _resolve_claimable(user_id, email, id_or_token)
    if share is None:
        return api.not_found("share not found or not addressed to you")

    # Idempotent: a re-claim by the same user returns the recorded result rather than forking again.
    if share.get("claimed"):
        if share.get("claimedBy") == user_id and share.get("claimResult"):
            return api.ok(share["claimResult"])
        return api.error(409, "share already claimed")

    result = _claim_into_library(user_id, share)

    # Mark the *original* share row claimed. It lives under the sharer's userId partition (stashed as
    # ownerUserId at creation, since the DynamoDB PK isn't a doc field), so rewrite it there — this
    # makes the claim visible to /shares/incoming (claimed shares are filtered out) and idempotent.
    share["claimed"] = True
    share["claimedBy"] = user_id
    share["claimedAt"] = _now()
    share["claimResult"] = result
    shares.put(share["ownerUserId"], share)
    return api.ok(result)


# --- dispatch -------------------------------------------------------------------------------------
def _method(event: dict) -> str:
    return (event.get("requestContext", {}).get("http", {}) or {}).get("method", "").upper()


@api.route
def handler(event: dict[str, Any], context: Any) -> dict:
    """API Gateway v2 (payload format 2.0) proxy entrypoint; dispatches the sharing routes.

    Routing keys off the path params declared in infra/shared/shares.tf: ``{token}`` for the link
    preview, ``{idOrToken}`` for claim. The two param-less routes are disambiguated by method —
    ``GET /shares/incoming`` is the only GET on the collection path, ``POST /shares`` the only POST.
    """
    method = _method(event)
    token = api.path_param(event, "token")
    id_or_token = api.path_param(event, "idOrToken")

    # POST /shares/{idOrToken}/claim
    if id_or_token is not None:
        if method == "POST":
            user_id = get_user_id(event)
            return _claim(user_id, event, id_or_token)
        return api.error(405, f"method {method or '?'} not allowed on this route")

    # GET /shares/{token}  (link preview — unauthenticated-friendly; auth deferred to #11)
    if token is not None:
        if method == "GET":
            return _preview(token)
        return api.error(405, f"method {method or '?'} not allowed on this route")

    # Param-less routes: GET /shares/incoming (the only GET here) and POST /shares.
    if method == "GET":
        return _incoming(get_user_id(event), event)
    if method == "POST":
        return _create(get_user_id(event), event)

    return api.error(405, f"method {method or '?'} not allowed on this route")
