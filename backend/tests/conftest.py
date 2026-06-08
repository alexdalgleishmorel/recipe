"""Shared pytest fixtures for the backend tests.

Makes the shared ``data_access`` layer importable without installing it, and stands up moto-mocked
DynamoDB tables whose schema mirrors ``infra/shared/tables.tf`` (PK ``userId`` / SK ``entityId``,
plus the ``email_index``, ``token_index``, and ``recipient_email_index`` GSIs).
"""

import os
import sys

import boto3
import pytest
from moto import mock_aws

# Make `import data_access` resolve to backend/layers/data_access without installing the package.
sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "layers")
)

# moto needs an AWS region + dummy creds in the environment before boto3 clients are built.
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")


def _create_entity_table(ddb, name, gsis=None):
    """Create a PK=userId / SK=entityId table, optionally with extra-attribute GSIs."""
    attrs = [
        {"AttributeName": "userId", "AttributeType": "S"},
        {"AttributeName": "entityId", "AttributeType": "S"},
    ]
    kwargs = {
        "TableName": name,
        "KeySchema": [
            {"AttributeName": "userId", "KeyType": "HASH"},
            {"AttributeName": "entityId", "KeyType": "RANGE"},
        ],
        "BillingMode": "PAY_PER_REQUEST",
    }
    if gsis:
        index_defs = []
        for index_name, index_key in gsis:
            attrs.append({"AttributeName": index_key, "AttributeType": "S"})
            index_defs.append(
                {
                    "IndexName": index_name,
                    "KeySchema": [{"AttributeName": index_key, "KeyType": "HASH"}],
                    "Projection": {"ProjectionType": "ALL"},
                }
            )
        kwargs["GlobalSecondaryIndexes"] = index_defs
    kwargs["AttributeDefinitions"] = attrs
    ddb.create_table(**kwargs)


@pytest.fixture
def dal(monkeypatch):
    """Yield the `data_access` module wired to fresh moto-mocked tables for one test.

    Tables are created under the same names the layer defaults to, so no env overrides are needed.
    Imported lazily inside the mock so its boto3 resource binds to the mocked backend.
    """
    with mock_aws():
        ddb = boto3.client("dynamodb", region_name="us-east-1")
        _create_entity_table(ddb, "recipe-recipes")
        _create_entity_table(ddb, "recipe-meal-plans")
        _create_entity_table(ddb, "recipe-collections")
        _create_entity_table(ddb, "recipe-users", gsis=[("email_index", "email")])
        _create_entity_table(
            ddb,
            "recipe-shares",
            gsis=[
                ("token_index", "token"),
                ("recipient_email_index", "recipientEmail"),
            ],
        )

        # Import after the mock is active and reset the lazily-built resource so it binds to moto.
        import data_access
        from data_access import tables

        tables._resource = None
        yield data_access
        tables._resource = None
