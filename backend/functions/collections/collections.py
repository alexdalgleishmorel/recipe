"""Collection CRUD handler (#16) — copies the recipes/plans Lambda pattern (#14/#15) for collections.

Backs ``CollectionsRepository`` (frontend/lib/services/repositories.dart) over the collections table:

    GET    /collections        -> list the caller's collections
    POST   /collections        -> create (server assigns a ``c<uuid>`` id)
    GET    /collections/{id}    -> read one
    PUT    /collections/{id}    -> upsert one (id taken from the path, not the body)
    DELETE /collections/{id}    -> delete one (idempotent)

Every operation is scoped to the caller's userId (``common.get_user_id``) and goes through the
``data_access`` layer — no DynamoDB wiring here. A single ``handler`` dispatches on the HTTP method
and the presence of the ``{id}`` path parameter (one Lambda, all five routes), which keeps the
Terraform handler map and the integration count small.
"""

from __future__ import annotations

import uuid
from typing import Any

from common import api, get_user_id
from data_access import collections

ID_PREFIX = "c"  # frontend collection ids look like "c12ab..."; keep server-assigned ids consistent.


def _new_id() -> str:
    """Generate a server-assigned collection id: the ``c`` prefix + a uuid4 hex (no dashes)."""
    return f"{ID_PREFIX}{uuid.uuid4().hex}"


def _list(user_id: str) -> dict:
    return api.ok(collections.list(user_id))


def _create(user_id: str, event: dict) -> dict:
    doc = api.body(event)
    # Server owns the id: ignore any client-supplied id and assign a fresh one.
    doc["id"] = _new_id()
    saved = collections.put(user_id, doc)
    return api.created(saved)


def _get(user_id: str, collection_id: str) -> dict:
    found = collections.get(user_id, collection_id)
    if found is None:
        return api.not_found(f"collection '{collection_id}' not found")
    return api.ok(found)


def _update(user_id: str, collection_id: str, event: dict) -> dict:
    doc = api.body(event)
    # The path id is authoritative; the stored item always carries it.
    doc["id"] = collection_id
    saved = collections.put(user_id, doc)
    return api.ok(saved)


def _delete(user_id: str, collection_id: str) -> dict:
    collections.delete(user_id, collection_id)  # idempotent at the DAL
    return api.no_content()


@api.route
def handler(event: dict[str, Any], context: Any) -> dict:
    """API Gateway v2 (payload format 2.0) proxy entrypoint; dispatches the five collection routes."""
    user_id = get_user_id(event)
    method = (event.get("requestContext", {}).get("http", {}) or {}).get("method", "").upper()
    collection_id = api.path_param(event, "id")

    if collection_id is None:
        if method == "GET":
            return _list(user_id)
        if method == "POST":
            return _create(user_id, event)
    else:
        if method == "GET":
            return _get(user_id, collection_id)
        if method == "PUT":
            return _update(user_id, collection_id, event)
        if method == "DELETE":
            return _delete(user_id, collection_id)

    return api.error(405, f"method {method or '?'} not allowed on this route")
