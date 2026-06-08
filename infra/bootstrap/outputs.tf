output "deploy_role_arn" {
  description = "Set as the GitHub Actions variable AWS_DEPLOY_ROLE_ARN (used by deploy workflows)."
  value       = aws_iam_role.deploy.arn
}

output "plan_role_arn" {
  description = "Set as the GitHub Actions variable AWS_PLAN_ROLE_ARN (used by PR build/plan)."
  value       = aws_iam_role.plan.arn
}

output "state_bucket" {
  description = "Terraform state bucket — referenced by the infra/shared backend."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "Terraform state lock table."
  value       = aws_dynamodb_table.lock.id
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
