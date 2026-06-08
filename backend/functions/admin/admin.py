"""Admin entitlement handler (#20) — copies the me/recipes/plans Lambda pattern.

Lets an admin toggle another user's ``canAiImport`` entitlement (frontend/lib/models/user.dart):

    POST /admin/entitlements  { userId, canAiImport: bool }
        -> set the target user's canAiImport and return the updated target profile

Authorization is read from the CALLER's *stored* profile, never the request: the caller is resolved
via ``common.get_user_id`` and looked up through the ``users`` accessor, and the call is rejected with
403 unless that stored profile's ``isAdmin`` is true. The target user (``userId`` from the body) is
looked up the same way; a missing target is a 404. ``isAdmin`` is intentionally not settable here —
only ``canAiImport`` is admin-controlled per this issue.

The owner (``ADMIN_EMAIL``) is bootstrapped as admin by #13's lazy-create on their first GET /me, so
there is no separate bootstrap step. Persistence goes through the ``data_access`` layer (the ``users``
accessor; the user's id is the table's sort key) — no DynamoDB wiring here.

TODO(#11): once the Cognito JWT authorizer is attached, the caller's identity comes from the verified
``sub`` claim; the admin check (stored isAdmin) is unchanged.
"""

from __future__ import annotations

from typing import Any

from common import api, get_user_id
from data_access import users


def _set_entitlement(event: dict, caller_id: str) -> dict:
    """Flip the target user's ``canAiImport`` (admin-only). Returns the updated target profile."""
    caller = users.get(caller_id, caller_id)
    if caller is None or not caller.get("isAdmin"):
        return api.error(403, "admin entitlement required")

    patch = api.body(event)
    target_id = patch.get("userId")
    if not target_id or not isinstance(target_id, str):
        return api.bad_request("userId is required")
    if "canAiImport" not in patch or not isinstance(patch["canAiImport"], bool):
        return api.bad_request("canAiImport (bool) is required")

    target = users.get(target_id, target_id)
    if target is None:
        return api.not_found(f"user {target_id} not found")

    target["canAiImport"] = patch["canAiImport"]
    saved = users.put(target_id, target)
    return api.ok(saved)


@api.route
def handler(event: dict[str, Any], context: Any) -> dict:
    """API Gateway v2 (payload format 2.0) proxy entrypoint for the /admin routes."""
    caller_id = get_user_id(event)
    method = (event.get("requestContext", {}).get("http", {}) or {}).get("method", "").upper()

    if method == "POST":
        return _set_entitlement(event, caller_id)

    return api.error(405, f"method {method or '?'} not allowed on this route")
