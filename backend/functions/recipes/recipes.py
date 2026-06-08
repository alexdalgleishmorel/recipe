"""Recipes CRUD handler (#14) — the reference API Lambda pattern (#15/#16 copy this shape).

Backs ``RecipesRepository`` (frontend/lib/services/repositories.dart) over the recipes table:

    GET    /recipes        -> list the caller's recipes
    POST   /recipes        -> create (server assigns an ``r<uuid>`` id)
    GET    /recipes/{id}    -> read one
    PUT    /recipes/{id}    -> upsert one (id taken from the path, not the body)
    DELETE /recipes/{id}    -> delete one (idempotent)

Every operation is scoped to the caller's userId (``common.get_user_id``) and goes through the
``data_access`` layer — no DynamoDB wiring here. A single ``handler`` dispatches on the HTTP method
and the presence of the ``{id}`` path parameter (one Lambda, all five routes), which keeps the
Terraform handler map and the integration count small.
"""

from __future__ import annotations

import uuid
from typing import Any

from common import api, get_user_id
from data_access import recipes

ID_PREFIX = "r"  # frontend ids look like "r12ab..."; keep server-assigned ids consistent.


def _new_id() -> str:
    """Generate a server-assigned recipe id: the ``r`` prefix + a uuid4 hex (no dashes)."""
    return f"{ID_PREFIX}{uuid.uuid4().hex}"


def _list(user_id: str) -> dict:
    return api.ok(recipes.list(user_id))


def _create(user_id: str, event: dict) -> dict:
    doc = api.body(event)
    # Server owns the id: ignore any client-supplied id and assign a fresh one.
    doc["id"] = _new_id()
    saved = recipes.put(user_id, doc)
    return api.created(saved)


def _get(user_id: str, recipe_id: str) -> dict:
    found = recipes.get(user_id, recipe_id)
    if found is None:
        return api.not_found(f"recipe '{recipe_id}' not found")
    return api.ok(found)


def _update(user_id: str, recipe_id: str, event: dict) -> dict:
    doc = api.body(event)
    # The path id is authoritative; the stored item always carries it.
    doc["id"] = recipe_id
    saved = recipes.put(user_id, doc)
    return api.ok(saved)


def _delete(user_id: str, recipe_id: str) -> dict:
    recipes.delete(user_id, recipe_id)  # idempotent at the DAL
    return api.no_content()


@api.route
def handler(event: dict[str, Any], context: Any) -> dict:
    """API Gateway v2 (payload format 2.0) proxy entrypoint; dispatches the five recipe routes."""
    user_id = get_user_id(event)
    method = (event.get("requestContext", {}).get("http", {}) or {}).get("method", "").upper()
    recipe_id = api.path_param(event, "id")

    if recipe_id is None:
        if method == "GET":
            return _list(user_id)
        if method == "POST":
            return _create(user_id, event)
    else:
        if method == "GET":
            return _get(user_id, recipe_id)
        if method == "PUT":
            return _update(user_id, recipe_id, event)
        if method == "DELETE":
            return _delete(user_id, recipe_id)

    return api.error(405, f"method {method or '?'} not allowed on this route")
