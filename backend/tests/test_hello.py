"""Smoke test: the hello handler imports and returns a JSON 200."""

import json
import os
import sys

# Make the hello function module importable without installing the package.
sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "functions", "hello")
)

import hello  # noqa: E402


def test_hello_returns_200():
    resp = hello.handler({}, None)
    assert resp["statusCode"] == 200


def test_hello_body_is_json():
    resp = hello.handler({}, None)
    body = json.loads(resp["body"])
    assert body["ok"] is True
    assert "message" in body
