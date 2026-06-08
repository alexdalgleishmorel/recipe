output "api_base_url" {
  description = "HTTP API base URL — the frontend's API transport target."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "lambda_role_arn" {
  description = "Execution role shared by the app Lambdas (grants extended per #12)."
  value       = aws_iam_role.lambda.arn
}
