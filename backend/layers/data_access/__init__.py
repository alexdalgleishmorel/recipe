"""Shared DynamoDB data-access layer (#12).

One table per entity (recipes, meal_plans, collections, users, shares), each partitioned by
``userId`` (PK) with ``entityId`` (SK). The CRUD Lambdas (#14-#16) import the per-entity accessors
exposed here so all DynamoDB wiring lives in one place.

Every operation is scoped to a ``user_id``: a list is a Query on the partition, and get/put/delete
target a single ``(user_id, entity_id)`` item. Two non-owner lookups are also exposed — resolving a
User by email (``users.get_by_email``) and a Share by token (``shares.get_by_token``) via GSIs — for
share-by-email and link shares respectively.

JSON shapes round-trip the Flutter models in ``frontend/lib/models`` verbatim: the entity's own JSON
(``toJson``/``fromJson``) is stored as the item body alongside the ``userId``/``entityId`` keys, with
floats stored as DynamoDB ``Decimal`` and converted back on read.

Typical use in a Lambda::

    from data_access import recipes

    recipes.put(user_id, recipe_dict)        # upsert
    recipe = recipes.get(user_id, recipe_id) # -> dict | None
    all_recipes = recipes.list(user_id)      # -> list[dict]
    recipes.delete(user_id, recipe_id)
"""

from .tables import (
    EntityTable,
    GsiLookupTable,
    collections,
    meal_plans,
    recipes,
    shares,
    users,
)

__all__ = [
    "EntityTable",
    "GsiLookupTable",
    "recipes",
    "meal_plans",
    "collections",
    "users",
    "shares",
]
