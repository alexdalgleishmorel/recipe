# backend — serverless Python backend

Python 3.12 Lambda code for the recipe app, deployed by `infra/shared`. The HTTP API + Lambda wiring
lives in Terraform; this dir holds the handler code, the shared data-access layer, and the build that
produces the deployable bundle.

```
backend/
├── functions/         ← one dir per Lambda; each module exposes a `handler(event, context)`
│   └── hello/         ← example handler behind GET /hello (proves the pattern)
├── layers/            ← shared code imported by handlers
│   └── data_access/   ← DynamoDB access layer (placeholder; filled in #12)
├── tests/             ← pytest
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

## Test

```bash
python3 -m pytest backend/tests
```

## What's next

Real handlers and the data-access layer arrive in later issues: auth (#11), DynamoDB tables (#12),
and recipes / meal-plan / grocery CRUD (#14-#16). Add a new function as `functions/<name>/<name>.py`
exposing `handler`, then extend the `local.handlers` / `local.routes` maps in `infra/shared/main.tf`.
