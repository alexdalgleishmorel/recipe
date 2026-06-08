# AWS bootstrap: OIDC federation + Terraform state backend

This is the **one-time** AWS setup that makes CI deploys keyless. You run it once, with your own AWS
admin credentials, on your machine. It is the only place your personal AWS credentials are used — they
never go into GitHub. Defined as Terraform in [`infra/bootstrap`](../infra/bootstrap).

## What it creates

- A **GitHub OIDC identity provider** (`token.actions.githubusercontent.com`).
- Two IAM roles, both trusting **only this repo** via the OIDC provider:
  - `recipe-gh-actions-plan` — read-only, assumable by any branch run in the repo; used by PR
    build / `terraform plan`.
  - `recipe-gh-actions-deploy` — write, assumable **only** from `main` or the gated `production`
    environment; used by deploy workflows.
- The **Terraform remote state backend**: a versioned, encrypted S3 bucket + a DynamoDB lock table
  (`recipe-tflock`).

## Create a dedicated IAM user for the bootstrap (recommended)

You *can* run the bootstrap with any admin identity, but it's cleaner to use a **recipe-specific IAM
user** (rather than a shared admin like `composable-site-platform-admin`) so this project's footprint
is isolated and its keys are easy to revoke afterward.

The bootstrap creates IAM (OIDC provider, roles, policies), S3, and DynamoDB resources, so the user
needs broad permissions for this one-time run. The pragmatic choice is `AdministratorAccess`, tightened
or removed once bootstrap is complete (see [Cleanup](#cleanup-after-bootstrap)).

Run these once, using your **existing admin** credentials (the identity from your `aws sts
get-caller-identity` check). They create the user in the *same* account (`696532327395`):

```bash
# 1. Create the dedicated user
aws iam create-user --user-name recipe-app-admin

# 2. Grant it admin for the one-time bootstrap (tighten/remove later)
aws iam attach-user-policy \
  --user-name recipe-app-admin \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# 3. Mint an access key — capture AccessKeyId + SecretAccessKey from the output (shown once)
aws iam create-access-key --user-name recipe-app-admin
```

Configure it as a **named local profile** called `recipe`, kept separate from your default/admin
profile so you opt in explicitly:

```bash
aws configure set aws_access_key_id     <AccessKeyId>     --profile recipe
aws configure set aws_secret_access_key <SecretAccessKey> --profile recipe
aws configure set region                us-east-1         --profile recipe
aws configure set output                json              --profile recipe

# Confirm the profile resolves to the new user in the right account
AWS_PROFILE=recipe aws sts get-caller-identity
# -> Account 696532327395, Arn ending in user/recipe-app-admin
```

## Run it (once)

```bash
cd infra/bootstrap
export AWS_PROFILE=recipe          # use the dedicated profile for every command in this stack
aws sts get-caller-identity        # sanity-check the account/user one more time

terraform init        # local state — this stack *creates* the remote backend
terraform apply       # review the plan, then approve
```

> Defaults already match this repo (`github_org=alexdalgleishmorel`, `github_repo=recipe`,
> `state_bucket_name=recipe-tfstate-alexdalgleishmorel`, `lock_table_name=recipe-tflock`,
> `aws_region=us-east-1`), so no `-var` flags are needed.

Bucket names are global; if `recipe-tfstate-alexdalgleishmorel` is taken, pass
`-var state_bucket_name=<something-unique>`.

## Wire the outputs into GitHub

```bash
terraform output
```

Add the two role ARNs as **repository variables** (Settings → Secrets and variables → Actions →
Variables — these are ARNs, not secrets):

- `AWS_DEPLOY_ROLE_ARN` = `deploy_role_arn`
- `AWS_PLAN_ROLE_ARN`   = `plan_role_arn`

Add the state backend identifiers as repository variables too (the deploy workflow passes them to
`terraform init -backend-config`):

- `TF_STATE_BUCKET` = `state_bucket`
- `TF_LOCK_TABLE`   = `lock_table`

Create a `production` environment (Settings → Environments) — optionally with required reviewers — so
deploy jobs are gated. No secrets are required for the hello-Lambda scaffold; later issues (#11) add
auth secrets in the `production` environment.

## Verify (no static keys anywhere)

A CI workflow runs `aws sts get-caller-identity` after assuming `recipe-gh-actions-plan` via OIDC. A
green run with **no** `AWS_ACCESS_KEY_ID` secret in the repo confirms federation works.

## Cleanup after bootstrap

Once bootstrap has applied and CI deploys work via OIDC, the `recipe-app-admin` keys are no longer
needed for day-to-day work (CI uses the OIDC roles, not these keys). To shrink the blast radius:

```bash
# Deactivate (reversible) — keep the key around in case you re-run bootstrap
aws iam update-access-key --user-name recipe-app-admin --access-key-id <AccessKeyId> --status Inactive

# …or delete the key outright once you're confident
aws iam delete-access-key --user-name recipe-app-admin --access-key-id <AccessKeyId>
```

If you do need to re-run bootstrap later (e.g. to change the OIDC trust), re-activate or mint a fresh
key first.

## Tightening later

`recipe-gh-actions-deploy` uses a broad service policy for the MVP (a handful of stacks). Once the
resource set stabilises, scope the actions in [`infra/bootstrap/oidc.tf`](../infra/bootstrap/oidc.tf)
to specific resource ARNs. `iam:*` is required because `infra/shared` creates the Lambda execution
role.
