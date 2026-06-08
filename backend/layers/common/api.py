"""HTTP request/response helpers for the API Gateway v2 (HTTP API, payload format 2.0) Lambdas.

Keeps the CRUD handlers declarative: they parse the request with :func:`path_param` / :func:`body`,
and return via :func:`json_response` (or the ``ok``/``created``/``no_content``/``not_found`` /
``bad_request`` shortcuts). The :func:`route` decorator wraps a handler to turn uncaught
:class:`ApiError` (and :class:`~common.auth.Unauthorized`) into clean JSON error responses, so each
operation stays focused on the happy path.
"""

from __future__ import annotations

import json
from functools import wraps
from typing import Any, Callable, Optional

from .auth import Unauthorized

JSON_HEADERS = {"content-type": "application/json"}


class ApiError(Exception):
    """An error that maps to an HTTP status + JSON body (raised by handlers, caught by :func:`route`)."""

    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def json_response(status: int, body: Any) -> dict:
    """Build an API Gateway v2 proxy response with a JSON-encoded body."""
    return {
        "statusCode": status,
        "headers": JSON_HEADERS,
        "body": json.dumps(body),
    }


def ok(body: Any) -> dict:
    """200 with ``body``."""
    return json_response(200, body)


def created(body: Any) -> dict:
    """201 with ``body`` (the newly created resource)."""
    return json_response(201, body)


def no_content() -> dict:
    """204 with an empty body (e.g. after DELETE)."""
    return {"statusCode": 204, "headers": JSON_HEADERS, "body": ""}


def error(status: int, message: str) -> dict:
    """An error response: ``{"error": message}`` at ``status``."""
    return json_response(status, {"error": message})


def not_found(message: str = "not found") -> dict:
    """404 error response."""
    return error(404, message)


def bad_request(message: str = "bad request") -> dict:
    """400 error response."""
    return error(400, message)


def path_param(event: dict, name: str) -> Optional[str]:
    """Return the ``{name}`` path parameter from the event, or ``None``."""
    params = (event or {}).get("pathParameters") or {}
    return params.get(name)


def body(event: dict) -> dict:
    """Parse the request body as a JSON object.

    Raises :class:`ApiError` (400) if the body is missing or not a JSON object.
    """
    raw = (event or {}).get("body")
    if raw is None or raw == "":
        raise ApiError(400, "request body is required")
    try:
        parsed = json.loads(raw)
    except (ValueError, TypeError):
        raise ApiError(400, "request body is not valid JSON")
    if not isinstance(parsed, dict):
        raise ApiError(400, "request body must be a JSON object")
    return parsed


def route(func: Callable[[dict, Any], dict]) -> Callable[[dict, Any], dict]:
    """Wrap a Lambda handler so raised :class:`ApiError`/:class:`Unauthorized` become JSON responses.

    Unexpected exceptions become a 500; everything else is returned unchanged.
    """

    @wraps(func)
    def wrapper(event: dict, context: Any) -> dict:
        try:
            return func(event, context)
        except Unauthorized as exc:
            return error(401, str(exc))
        except ApiError as exc:
            return error(exc.status, exc.message)
        except Exception:  # noqa: BLE001 - last-resort guard; details go to CloudWatch, not the client
            return error(500, "internal server error")

    return wrapper
