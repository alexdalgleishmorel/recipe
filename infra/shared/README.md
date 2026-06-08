# infra/shared — app stack (Terraform)

The **deploy-once** application backend. Today it stands up a single `hello` Lambda behind an HTTP API
Gateway v2 to prove the packaging + integration pattern. Real resources land in later issues:

- **#11** — Cognito user pool + JWT authorizer on the routes
- **#12** — DynamoDB tables (recipes, plans, grocery) + IAM grants on the exec role
- **#14-#16** — recipes / meal-plan / grocery-list CRUD Lambdas + routes

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
