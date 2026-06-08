"""Admin handler (#20, #65) — copies the me/recipes/plans Lambda pattern.

Backs the admin-only routes (frontend/lib/models/user.dart):

    POST /admin/entitlements  { userId, canAiImport: bool }
        -> set the target user's canAiImport and return the updated target profile
    GET  /admin/users
        -> list every user as [{ id, email, displayName, canAiImport, isAdmin }] (#65)

Authorization is read from the CALLER's *stored* profile, never the request: the caller is resolved
via ``common.get_user_id`` and looked up through the ``users`` accessor, and every route is rejected
with 403 unless that stored profile's ``isAdmin`` is true. For POST /admin/entitlements the target
user (``userId`` from the body) is looked up the same way; a missing target is a 404. ``isAdmin`` is
intentionally not settable here — only ``canAiImport`` is admin-controlled per this issue.

GET /admin/users scans the whole users table (``users.list_all``, requires ``dynamodb:Scan`` on the
exec role). Only users who have signed in at least once exist — profiles are lazy-created on the first
GET /me (#13) — so the list is exactly the signed-in users, which is expected.

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


# Fields returned for each user by GET /admin/users (the #65 contract / user.dart shape). Selected
# explicitly so the stored doc never leaks extra attributes to the admin UI.
USER_FIELDS = ("id", "email", "displayName", "canAiImport", "isAdmin")


def _require_admin(caller_id: str) -> None:
    """Reject the caller with 403 unless their STORED profile has ``isAdmin`` true."""
    caller = users.get(caller_id, caller_id)
    if caller is None or not caller.get("isAdmin"):
        raise api.ApiError(403, "admin entitlement required")


def _user_view(profile: dict) -> dict:
    """Project a stored user profile down to the GET /admin/users contract fields."""
    return {
        "id": profile.get("id", ""),
        "email": profile.get("email", ""),
        "displayName": profile.get("displayName", ""),
        "canAiImport": bool(profile.get("canAiImport", False)),
        "isAdmin": bool(profile.get("isAdmin", False)),
    }


def _list_users(caller_id: str) -> dict:
    """List every user (admin-only). Returns the #65 contract array of user objects."""
    _require_admin(caller_id)
    return api.ok([_user_view(u) for u in users.list_all()])


def _set_entitlement(event: dict, caller_id: str) -> dict:
    """Flip the target user's ``canAiImport`` (admin-only). Returns the updated target profile."""
    _require_admin(caller_id)

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
    """API Gateway v2 (payload format 2.0) proxy entrypoint; dispatches the /admin routes on method+path."""
    caller_id = get_user_id(event)
    http = event.get("requestContext", {}).get("http", {}) or {}
    method = (http.get("method") or "").upper()
    path = http.get("path") or ""

    if method == "POST" and path.endswith("/admin/entitlements"):
        return _set_entitlement(event, caller_id)
    if method == "GET" and path.endswith("/admin/users"):
        return _list_users(caller_id)

    return api.error(405, f"{method or '?'} {path or '?'} not allowed on this route")
