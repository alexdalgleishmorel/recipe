"""Caller-identity resolution for the API Lambdas.

Every entity is partitioned by ``userId`` in DynamoDB, so each request must resolve exactly one
caller id. The production source is the API Gateway JWT authorizer (Cognito): API Gateway validates
the bearer token and exposes the verified claims at
``event["requestContext"]["authorizer"]["jwt"]["claims"]``, where ``sub`` is the stable user id.

TODO(#11): the Cognito user pool + JWT authorizer are not attached to the routes yet, so production
requests carry no authorizer context. Until then we fall back to a dev identity — an ``x-user-id``
request header, else the ``DEV_USER_ID`` env var. When #11 lands, the authorizer is attached in
``infra/shared`` and this fallback becomes dead code (the ``jwt.claims.sub`` branch always wins);
delete the fallback then so unauthenticated requests are rejected. This helper is the single
swap point — no handler reads identity directly.
"""

from __future__ import annotations

import os
from typing import Any, Optional

# Header a dev/test client sends to act as a given user while the authorizer is deferred (#11).
DEV_USER_HEADER = "x-user-id"
DEV_USER_ENV = "DEV_USER_ID"


class Unauthorized(Exception):
    """Raised when no caller identity can be resolved from the request."""


def _jwt_sub(event: dict) -> Optional[str]:
    """Return the verified ``sub`` claim from the JWT authorizer context, if present."""
    ctx = (event or {}).get("requestContext") or {}
    authorizer = ctx.get("authorizer") or {}
    claims = (authorizer.get("jwt") or {}).get("claims") or {}
    sub = claims.get("sub")
    return sub or None


def _header(event: dict, name: str) -> Optional[str]:
    """Case-insensitive lookup of a request header (API Gateway v2 lower-cases keys, but be safe)."""
    headers = (event or {}).get("headers") or {}
    target = name.lower()
    for key, value in headers.items():
        if isinstance(key, str) and key.lower() == target:
            return value
    return None


def get_user_id(event: dict[str, Any]) -> str:
    """Resolve the caller's userId for ``event``.

    Order: the JWT authorizer's ``sub`` claim (production), then the ``x-user-id`` dev header, then
    the ``DEV_USER_ID`` env var. Raises :class:`Unauthorized` if none resolve.
    """
    sub = _jwt_sub(event)
    if sub:
        return sub

    # TODO(#11): remove the dev fallbacks once the JWT authorizer is attached to the routes.
    header_user = _header(event, DEV_USER_HEADER)
    if header_user:
        return header_user

    env_user = os.environ.get(DEV_USER_ENV)
    if env_user:
        return env_user

    raise Unauthorized("no caller identity (no JWT claims, x-user-id header, or DEV_USER_ID)")
