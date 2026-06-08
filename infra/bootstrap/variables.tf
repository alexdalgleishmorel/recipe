variable "aws_region" {
  description = "Region for the state backend and IAM."
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub org/user that owns the repo allowed to assume the deploy role."
  type        = string
  default     = "alexdalgleishmorel"
}

variable "github_repos" {
  description = "Repository name(s) scoped in the OIDC trust policy. Includes both 'recipe' and 'recipes' to cover the repo rename."
  type        = list(string)
  default     = ["recipe", "recipes"]
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state."
  type        = string
  default     = "recipe-tfstate-alexdalgleishmorel"
}

variable "lock_table_name" {
  description = "DynamoDB table for Terraform state locking."
  type        = string
  default     = "recipe-tflock"
}

variable "create_oidc_provider" {
  description = "Create the account-global GitHub OIDC provider. Leave false when another stack in this AWS account (e.g. composable-site-platform) already created token.actions.githubusercontent.com; the existing provider is referenced via a data source instead."
  type        = bool
  default     = false
}

variable "deploy_environment" {
  description = "GitHub Actions environment that gates the deploy role (extra scope on the trust policy)."
  type        = string
  default     = "production"
}
