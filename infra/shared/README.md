# infra/shared — app stack (Terraform)

The **deploy-once** application backend. Today it stands up a single `hello` Lambda behind an HTTP API
Gateway v2 to prove the packaging + integration pattern. Real resources land in later issues:

- **#11** — Cognito user pool + JWT authorizer on the routes
- **#12** — DynamoDB tables + IAM grants on the exec role  — **done** (`tables.tf`)
- **#14-#16** — recipes / meal-plan / grocery-list CRUD Lambdas + routes

### DynamoDB tables (#12, `tables.tf`)

One table per entity, all `PAY_PER_REQUEST`, partitioned by owner: **PK `userId`, SK `entityId`**.

| Table                 | GSI           | GSI key | Purpose                       |
| --------------------- | ------------- | ------- | ----------------------------- |
| `recipe-recipes`      | —             | —       | recipes                       |
| `recipe-meal-plans`   | —             | —       | meal plans                    |
| `recipe-collections`  | —             | —       | recipe collections            |
| `recipe-users`        | `email_index` | `email` | resolve user for share-by-email |
| `recipe-shares`       | `token_index` | `token` | resolve share for link shares |

Sharing is fork-copy (a share materializes a copy under the recipient's `userId`), so reads never
cross partitions; the two GSIs cover the only non-owner lookups. Table names are output as
`dynamodb_tables` and injected into the Lambdas via `lambda_env` (`RECIPES_TABLE`, …); the exec role
gets item-level DynamoDB ops on exactly these table arns (+ `index/*`). The Python access layer over
these tables lives in `backend/layers/data_access`.

Resources are organized by concern in their own files (e.g. `recipes.tf`); the Lambda set is driven by
the `local.handlers` / `local.routes` maps in `main.tf`. No child modules.

## Apply (CI does this; manual form)

The Lambda zip is produced from a pre-built dist dir — run `backend/build.sh` first so
`var.lambda_dist_dir` (`../../backend/dist`) has vendored deps to package.

```bash
cd backend && ./build.sh && cd ../infra/shared

terraform init \
  -backend-config="bucket=<state bucket from bootstrap>" \
  -backend-config="dynamodb_table=<lock table>" \
  -backend-config="region=us-east-1"
terraform apply
```

## GitHub config the deploy workflow needs

- Variables: `AWS_DEPLOY_ROLE_ARN`, `TF_STATE_BUCKET`, `TF_LOCK_TABLE`

> No `.tfvars` — variables come from `TF_VAR_*` at apply time.
