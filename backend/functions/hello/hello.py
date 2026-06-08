"""Hello handler — the example Lambda proving the API Gateway v2 (HTTP API) pattern.

Wired to `GET /hello` in infra/shared. Returns a simple JSON 200. Real CRUD handlers (recipes,
plans, grocery) land in #14-#16 and share the data-access layer under ../../layers/.
"""

import json


def handler(event, context):
    """API Gateway v2 (HTTP API, payload format 2.0) proxy handler."""
    body = {
        "message": "hello from the recipe backend",
        "ok": True,
    }
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }
