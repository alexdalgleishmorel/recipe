# ---------------------------------------------------------------------------------------------------
# GitHub Actions OIDC federation — keyless CI deploys. No long-lived AWS keys ever live in GitHub.
# Workflows assume one of these roles via AssumeRoleWithWebIdentity; AWS verifies the GitHub-signed
# token against the OIDC provider and the role trust policy (scoped to THIS repo).
# ---------------------------------------------------------------------------------------------------

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

locals {
  repo_sub_prefix = "repo:${var.github_org}/${var.github_repo}"
}

# --- Trust policies -------------------------------------------------------------------------------

# Read-only plan role. Scoped to branch pushes in THIS repo only — NOT pull_request. Because a fork
# PR and a same-repo PR share the identical OIDC subject (repo:OWNER/REPO:pull_request), the trust
# policy cannot distinguish them; so PRs are excluded here entirely. If a PR `terraform plan` job is
# added later, gate it in the workflow with `if: …head.repo.full_name == github.repository` (skip
# forks) before re-allowing a pull_request subject.
data "aws_iam_policy_document" "plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.repo_sub_prefix}:ref:refs/heads/*"]
    }
  }
}

# Deploy role: only runs on main or in the gated `production` environment may assume it.
data "aws_iam_policy_document" "deploy_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.repo_sub_prefix}:ref:refs/heads/main",
        "${local.repo_sub_prefix}:environment:${var.deploy_environment}",
      ]
    }
  }
}

# --- Roles ----------------------------------------------------------------------------------------

resource "aws_iam_role" "plan" {
  name               = "recipe-gh-actions-plan"
  description        = "Read-only role for PR `terraform plan` / build checks (GitHub OIDC)."
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

resource "aws_iam_role" "deploy" {
  name               = "recipe-gh-actions-deploy"
  description        = "Deploy role for terraform apply on main / production (GitHub OIDC)."
  assume_role_policy = data.aws_iam_policy_document.deploy_trust.json
}

# --- Permissions ----------------------------------------------------------------------------------

# Both roles need to read/write Terraform state.
data "aws_iam_policy_document" "state_access" {
  statement {
    sid     = "StateBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
  }
  statement {
    sid       = "StateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.lock.arn]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "tfstate-access"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_access.json
}

resource "aws_iam_role_policy" "deploy_state" {
  name   = "tfstate-access"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.state_access.json
}

# Plan only needs to read the world.
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Deploy needs to manage the app stack's services. Broad for the MVP (a handful of stacks); tighten to
# resource ARNs once the resource set stabilises. iam:* is required to create the Lambda execution
# roles in infra/shared.
data "aws_iam_policy_document" "deploy_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "s3:*",
      "cloudfront:*",
      "acm:*",
      "route53:*",
      "dynamodb:*",
      "lambda:*",
      "apigateway:*",
      "cognito-idp:*",
      "cognito-identity:*",
      "logs:*",
      "iam:*",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy_permissions" {
  name   = "recipe-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy_permissions.json
}
