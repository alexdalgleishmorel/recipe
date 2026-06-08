terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Bootstrap runs ONCE with local state — it is what *creates* the remote state backend (the S3
  # bucket + DynamoDB lock table) that every other Terraform root then uses. After apply, commit
  # nothing sensitive; terraform.tfstate here is gitignored.
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = "recipe"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
