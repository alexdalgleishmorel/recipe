# backend — serverless Python backend

Python 3.12 Lambda code for the recipe app, deployed by `infra/shared`. The HTTP API + Lambda wiring
lives in Terraform; this dir holds the handler code, the shared data-access layer, and the build that
produces the deployable bundle.

```
backend/
├── functions/         ← one dir per Lambda; each module exposes a `handler(event, context)`
│   └── hello/         ← example handler behind GET /hello (proves the pattern)
├── layers/            ← shared code imported by handlers
│   └── data_access/   ← DynamoDB access layer (#12): per-entity get/list/put/delete + GSI lookups
├── tests/             ← pytest (DAL tests use moto; deps in tests/requirements-dev.txt)
└── build.sh           ← builds backend/dist (the dir Terraform's archive_file zips)
```

## Build the deploy bundle

`infra/shared` packages `backend/dist` via `archive_file`. Produce it with:

```bash
./build.sh        # -> backend/dist (handlers + layers + vendored deps, flattened)
```

The bundle is flat: each function module sits at the top level so the Terraform `handler` string
`"<module>.<function>"` (e.g. `hello.handler`) resolves, alongside the `data_access` package and any
pip-vendored dependencies.

## Data-access layer (`layers/data_access`, #12)

DynamoDB wiring for every persistent entity, one table per entity, all owner-partitioned (PK
`userId`, SK `entityId`) — see `infra/shared/tables.tf`. Each accessor scopes its ops to a `user_id`:

```python
from data_access import recipes, users, shares

recipes.put(user_id, recipe_dict)        # upsert (recipe_dict == Recipe.toJson())
recipes.get(user_id, recipe_id)          # -> dict | None
recipes.list(user_id)                    # -> list[dict]  (Query on the user's partition)
recipes.delete(user_id, recipe_id)

users.get_by_email("a@b.com")            # email_index GSI — share-by-email
shares.get_by_token("tok-...")           # token_index GSI — link shares
```

Accessors: `recipes`, `meal_plans`, `collections`, `users`, `shares`. The entity's model JSON is
stored intact under a `doc` attribute (so a model field like Share's own `entityId` can't collide
with the key attributes); GSI keys (`email`, `token`) are also copied to top-level attributes so the
indexes can find the row. Floats round-trip via `Decimal`. Table names come from the env vars
Terraform injects (`RECIPES_TABLE`, …), defaulting to the `recipe-*` names.

## Test

```bash
python3 -m pip install -r tests/requirements-dev.txt   # boto3 + moto + pytest
python3 -m pytest backend/tests
```

The DAL tests mock DynamoDB with `moto`, standing up tables that mirror `infra/shared/tables.tf`.

## What's next

Real CRUD handlers arrive in later issues: auth (#11), recipes / meal-plan / grocery CRUD
(#14-#16) — each importing the `data_access` accessors above. Add a new function as
`functions/<name>/<name>.py` exposing `handler`, then extend the `local.handlers` / `local.routes`
maps in `infra/shared/main.tf`.
