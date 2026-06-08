"""User profile + entitlements handler (#13) — copies the recipes/plans/collections Lambda pattern.

Backs the caller's own ``User`` record (frontend/lib/models/user.dart) over the users table:

    GET  /me   -> return the caller's profile; lazy-create it on first call
    PUT  /me   -> update mutable profile fields (displayName)

The Cognito post-confirmation trigger that would seed the profile is deferred (#11), so there is no
row until the first ``GET /me``. That call lazy-creates one: the id is the caller's userId
(``common.get_user_id``), the email comes from the JWT ``email`` claim (or the ``x-user-email`` dev
header), the displayName from a ``name`` claim or the email local-part, ``canAiImport`` defaults to
false, and ``isAdmin`` is true only when the email matches ``ADMIN_EMAIL``.

Entitlement flags (``isAdmin``, ``canAiImport``) are admin-controlled (#20) — a caller can never set
them on themselves, so ``PUT /me`` ignores those fields and only updates ``displayName``.

Every operation is scoped to the caller's userId and goes through the ``data_access`` layer (the
``users`` accessor; the user's id is the table's sort key) — no DynamoDB wiring here. A single
``handler`` dispatches on the HTTP method (one Lambda, both routes).
"""

from __future__ import annotations

import os
from typing import Any, Optional

from common import api, get_user_email, get_user_id, jwt_name
from data_access import users

# Email granted admin entitlements at profile creation. Set from Terraform's lambda_env (ADMIN_EMAIL);
# the default keeps local/dev parity with infra/shared/variables.tf's admin_email.
ADMIN_EMAIL_ENV = "ADMIN_EMAIL"

# Fields a caller may set via PUT /me. Entitlements (isAdmin, canAiImport) are admin-controlled (#20)
# and id/email are identity-derived, so all are excluded from caller-driven updates.
MUTABLE_FIELDS = ("displayName",)


def _admin_email() -> str:
    """The configured admin email (lower-cased for case-insensitive comparison); '' if unset."""
    return (os.environ.get(ADMIN_EMAIL_ENV) or "").strip().lower()


def _display_name(email: Optional[str], name: Optional[str]) -> str:
    """Pick a display name: an explicit ``name`` claim, else the email local-part, else ''."""
    if name:
        return name
    if email and "@" in email:
        return email.split("@", 1)[0]
    return email or ""


def _new_profile(event: dict, user_id: str) -> dict:
    """Build a fresh ``User`` profile (user.dart toJson shape) for ``user_id`` from the request."""
    email = get_user_email(event)
    is_admin = bool(email) and email.strip().lower() == _admin_email() and _admin_email() != ""
    return {
        "id": user_id,
        "email": email or "",
        "displayName": _display_name(email, jwt_name(event)),
        "canAiImport": False,
        "isAdmin": is_admin,
    }


def _get(event: dict, user_id: str) -> dict:
    """Return the caller's profile, lazy-creating (and persisting) it on first call."""
    found = users.get(user_id, user_id)
    if found is not None:
        return api.ok(found)
    created = users.put(user_id, _new_profile(event, user_id))
    return api.ok(created)


def _update(event: dict, user_id: str) -> dict:
    """Update the caller's mutable profile fields. Lazy-creates first if no profile exists yet.

    Entitlement fields (isAdmin/canAiImport) and identity fields (id/email) in the body are ignored —
    only ``displayName`` is applied — so a caller can never escalate their own privileges via PUT.
    """
    patch = api.body(event)
    profile = users.get(user_id, user_id) or _new_profile(event, user_id)
    for field in MUTABLE_FIELDS:
        if field in patch:
            profile[field] = patch[field]
    saved = users.put(user_id, profile)
    return api.ok(saved)


@api.route
def handler(event: dict[str, Any], context: Any) -> dict:
    """API Gateway v2 (payload format 2.0) proxy entrypoint; dispatches the two /me routes."""
    user_id = get_user_id(event)
    method = (event.get("requestContext", {}).get("http", {}) or {}).get("method", "").upper()

    if method == "GET":
        return _get(event, user_id)
    if method == "PUT":
        return _update(event, user_id)

    return api.error(405, f"method {method or '?'} not allowed on this route")
