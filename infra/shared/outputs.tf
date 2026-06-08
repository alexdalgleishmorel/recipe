output "api_base_url" {
  description = "HTTP API base URL — the frontend's API transport target."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "lambda_role_arn" {
  description = "Execution role shared by the app Lambdas (granted item-level DynamoDB ops per #12)."
  value       = aws_iam_role.lambda.arn
}

output "uploads_bucket" {
  description = "Private S3 bucket holding recipe images; the uploads handler presigns PUTs to it (#17)."
  value       = aws_s3_bucket.uploads.bucket
}

# --- DynamoDB table names (#12) — consumed by the CRUD Lambdas via lambda_env (RECIPES_TABLE, ...) --
output "dynamodb_tables" {
  description = "DynamoDB table names by entity, keyed for the data-access layer / future CRUD Lambdas."
  value = {
    recipes     = aws_dynamodb_table.recipes.name
    meal_plans  = aws_dynamodb_table.meal_plans.name
    collections = aws_dynamodb_table.collections.name
    users       = aws_dynamodb_table.users.name
    shares      = aws_dynamodb_table.shares.name
  }
}

# --- Cognito auth (#11) — consumed by the frontend's OAuth config (Hosted UI + JWT) ----------------
output "cognito_user_pool_id" {
  description = "Cognito user pool id (also the JWT issuer path segment)."
  value       = aws_cognito_user_pool.users.id
}

output "cognito_app_client_id" {
  description = "Public SPA app client id (the ID token's `aud` and the authorizer's audience)."
  value       = aws_cognito_user_pool_client.spa.id
}

output "cognito_domain" {
  description = "Full Hosted UI base URL for the Cognito OAuth flow."
  value       = "https://${aws_cognito_user_pool_domain.hosted_ui.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "cognito_region" {
  description = "AWS region the Cognito user pool lives in (issuer/Hosted UI host)."
  value       = var.aws_region
}
