"""Meal-plan CRUD handler (#15) — copies the recipes Lambda pattern (#14) for meal plans.

Backs ``MealPlansRepository`` (frontend/lib/services/repositories.dart) over the meal-plans table:

    GET    /plans        -> list the caller's plans
    POST   /plans        -> create (server assigns a ``p<uuid>`` id)
    GET    /plans/{id}    -> read one
    PUT    /plans/{id}    -> upsert one (id taken from the path, not the body)
    DELETE /plans/{id}    -> delete one (idempotent)

Every operation is scoped to the caller's userId (``common.get_user_id``) and goes through the
``data_access`` layer — no DynamoDB wiring here. A single ``handler`` dispatches on the HTTP method
and the presence of the ``{id}`` path parameter (one Lambda, all five routes), which keeps the
Terraform handler map and the integration count small.
"""

from __future__ import annotations

import uuid
from typing import Any

from common import api, get_user_id
from data_access import meal_plans

ID_PREFIX = "p"  # frontend plan ids look like "p12ab..."; keep server-assigned ids consistent.


def _new_id() -> str:
    """Generate a server-assigned plan id: the ``p`` prefix + a uuid4 hex (no dashes)."""
    return f"{ID_PREFIX}{uuid.uuid4().hex}"


def _list(user_id: str) -> dict:
    return api.ok(meal_plans.list(user_id))


def _create(user_id: str, event: dict) -> dict:
    doc = api.body(event)
    # Server owns the id: ignore any client-supplied id and assign a fresh one.
    doc["id"] = _new_id()
    saved = meal_plans.put(user_id, doc)
    return api.created(saved)


def _get(user_id: str, plan_id: str) -> dict:
    found = meal_plans.get(user_id, plan_id)
    if found is None:
        return api.not_found(f"plan '{plan_id}' not found")
    return api.ok(found)


def _update(user_id: str, plan_id: str, event: dict) -> dict:
    doc = api.body(event)
    # The path id is authoritative; the stored item always carries it.
    doc["id"] = plan_id
    saved = meal_plans.put(user_id, doc)
    return api.ok(saved)


def _delete(user_id: str, plan_id: str) -> dict:
    meal_plans.delete(user_id, plan_id)  # idempotent at the DAL
    return api.no_content()


@api.route
def handler(event: dict[str, Any], context: Any) -> dict:
    """API Gateway v2 (payload format 2.0) proxy entrypoint; dispatches the five plan routes."""
    user_id = get_user_id(event)
    method = (event.get("requestContext", {}).get("http", {}) or {}).get("method", "").upper()
    plan_id = api.path_param(event, "id")

    if plan_id is None:
        if method == "GET":
            return _list(user_id)
        if method == "POST":
            return _create(user_id, event)
    else:
        if method == "GET":
            return _get(user_id, plan_id)
        if method == "PUT":
            return _update(user_id, plan_id, event)
        if method == "DELETE":
            return _delete(user_id, plan_id)

    return api.error(405, f"method {method or '?'} not allowed on this route")
