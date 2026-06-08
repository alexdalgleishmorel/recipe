"""Per-entity DynamoDB accessors over boto3.

Schema (set in ``infra/shared/tables.tf``): every table has PK ``userId`` (S) and SK ``entityId``
(S), ``PAY_PER_REQUEST``. The ``users`` table has an ``email_index`` GSI (HASH = ``email``); the
``shares`` table a ``token_index`` GSI (HASH = ``token``).

An item is ``{userId, entityId, doc: <entity JSON...>, <GSI keys...>}``: the Flutter model's own
``toJson`` map is stored intact under the ``doc`` attribute (so a model field can't collide with the
``userId``/``entityId`` key attributes — the Share model, e.g., has its own ``entityId`` field), and
``get``/``list`` return that ``doc`` back unchanged so it ``fromJson``s directly. Any GSI key
(``email``, ``token``) is also copied to a top-level attribute so the index can find the item.

DynamoDB has no float type, so floats are stored as ``Decimal`` on write and converted back on read —
the round-trip is value-preserving for the model shapes (mostly strings/ints with a few nested lists).
"""

from __future__ import annotations

import os
from decimal import Decimal
from typing import Any, Optional

import boto3
from boto3.dynamodb.conditions import Key

# --- attribute names (mirror infra/shared/tables.tf) ----------------------------------------------
PK = "userId"
SK = "entityId"
DOC = "doc"  # the entity's model JSON, nested so its fields can't collide with PK/SK

_resource = None


def _table(name: str):
    """Return the boto3 Table handle for ``name``, creating the resource lazily.

    The resource is built on first use (not at import) so importing this module never requires AWS
    credentials/region — tests point boto3 at moto, Lambdas pick up the runtime's env.
    """
    global _resource
    if _resource is None:
        _resource = boto3.resource("dynamodb")
    return _resource.Table(name)


def _to_dynamo(value: Any) -> Any:
    """Recursively convert a JSON-ish value to a DynamoDB-storable one (float -> Decimal)."""
    if isinstance(value, bool):
        return value
    if isinstance(value, float):
        # str() then Decimal avoids binary float artifacts (e.g. 1.1 -> 1.1, not 1.1000000000000001).
        return Decimal(str(value))
    if isinstance(value, list):
        return [_to_dynamo(v) for v in value]
    if isinstance(value, dict):
        return {k: _to_dynamo(v) for k, v in value.items()}
    return value


def _from_dynamo(value: Any) -> Any:
    """Recursively convert a value read from DynamoDB back to plain JSON (Decimal -> int/float)."""
    if isinstance(value, Decimal):
        # Whole numbers come back as int (matches the model's int fields); others as float.
        return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value, list):
        return [_from_dynamo(v) for v in value]
    if isinstance(value, dict):
        return {k: _from_dynamo(v) for k, v in value.items()}
    return value


def _read_doc(item: Optional[dict]) -> Optional[dict]:
    """Extract and decode the model JSON from a stored item (``None`` passthrough)."""
    if item is None:
        return None
    return _from_dynamo(item.get(DOC, {}))


class EntityTable:
    """A userId-partitioned entity table with item-level CRUD scoped to a single user.

    ``id_field`` is the model's identifier field (default ``"id"``); its value is stored as the SK.
    """

    def __init__(self, env_var: str, default_name: str, id_field: str = "id"):
        self._env_var = env_var
        self._default_name = default_name
        self.id_field = id_field

    @property
    def name(self) -> str:
        """Resolve the table name from the env var (set by Terraform), falling back to the default."""
        return os.environ.get(self._env_var, self._default_name)

    def _to_item(self, user_id: str, model: dict) -> dict:
        """Build the stored item: keys + the model nested under ``doc`` (overridable by subclasses)."""
        entity_id = model.get(self.id_field)
        if not entity_id:
            raise ValueError(f"model is missing required '{self.id_field}' field")
        return {PK: user_id, SK: str(entity_id), DOC: _to_dynamo(model)}

    def put(self, user_id: str, model: dict) -> dict:
        """Upsert ``model`` (a model ``toJson`` dict) under ``user_id``. Returns the stored model.

        The model must carry its id under ``id_field``; that becomes the sort key.
        """
        _table(self.name).put_item(Item=self._to_item(user_id, model))
        return model

    def get(self, user_id: str, entity_id: str) -> Optional[dict]:
        """Fetch one item by ``(user_id, entity_id)``. Returns the model JSON, or ``None``."""
        resp = _table(self.name).get_item(Key={PK: user_id, SK: str(entity_id)})
        return _read_doc(resp.get("Item"))

    def list(self, user_id: str) -> list[dict]:
        """Return all of ``user_id``'s items (a Query on the partition), as model JSON dicts."""
        items: list[dict] = []
        kwargs: dict[str, Any] = {"KeyConditionExpression": Key(PK).eq(user_id)}
        table = _table(self.name)
        while True:
            resp = table.query(**kwargs)
            items.extend(resp.get("Items", []))
            start = resp.get("LastEvaluatedKey")
            if not start:
                break
            kwargs["ExclusiveStartKey"] = start
        return [_read_doc(i) for i in items]

    def delete(self, user_id: str, entity_id: str) -> None:
        """Delete one item by ``(user_id, entity_id)``. Idempotent (no error if absent)."""
        _table(self.name).delete_item(Key={PK: user_id, SK: str(entity_id)})


class GsiLookupTable(EntityTable):
    """An entity table that also supports a global-secondary-index lookup on one attribute.

    Used for the non-owner lookups: User by ``email`` and Share by ``token``. The GSI key is copied
    from the model to a top-level item attribute on write so the index can find it; the lookup is a
    Query on the GSI and returns the first matching item's model JSON (or ``None``).
    """

    def __init__(
        self,
        env_var: str,
        default_name: str,
        index_name: str,
        index_key: str,
        id_field: str = "id",
    ):
        super().__init__(env_var, default_name, id_field=id_field)
        self.index_name = index_name
        self.index_key = index_key

    def _to_item(self, user_id: str, model: dict) -> dict:
        item = super()._to_item(user_id, model)
        value = model.get(self.index_key)
        # Promote the GSI key (email/token) to a top-level attribute so the index indexes it. Skip
        # empty/missing values: DynamoDB rejects an empty string as an indexed key attribute, and an
        # item with no value for the key is simply absent from the GSI (e.g. a profile created before
        # an email is known — #13's lazy-create when no email claim/header is present).
        if value:
            item[self.index_key] = value
        return item

    def get_by_index(self, value: str) -> Optional[dict]:
        """Resolve a single item by the GSI key ``value`` (e.g. an email or token)."""
        resp = _table(self.name).query(
            IndexName=self.index_name,
            KeyConditionExpression=Key(self.index_key).eq(value),
            Limit=1,
        )
        items = resp.get("Items", [])
        return _read_doc(items[0]) if items else None


# --- configured accessors (env var -> name from Terraform's lambda_env; defaults match tables.tf) --
recipes = EntityTable("RECIPES_TABLE", "recipe-recipes")
meal_plans = EntityTable("MEAL_PLANS_TABLE", "recipe-meal-plans")
collections = EntityTable("COLLECTIONS_TABLE", "recipe-collections")
users = GsiLookupTable("USERS_TABLE", "recipe-users", "email_index", "email")
shares = GsiLookupTable("SHARES_TABLE", "recipe-shares", "token_index", "token")

# Semantic aliases for the two GSI lookups (read better at call sites than get_by_index).
users.get_by_email = users.get_by_index  # type: ignore[attr-defined]
shares.get_by_token = shares.get_by_index  # type: ignore[attr-defined]
