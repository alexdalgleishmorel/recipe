output "api_base_url" {
  description = "HTTP API base URL — the frontend's API transport target."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "lambda_role_arn" {
  description = "Execution role shared by the app Lambdas (granted item-level DynamoDB ops per #12)."
  value       = aws_iam_role.lambda.arn
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
