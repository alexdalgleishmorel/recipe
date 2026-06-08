data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ===================================================================================================
# This root is the app stack. Today it stands up a single "hello" Lambda behind an HTTP API to prove
# the packaging + integration pattern end to end. The real surface area lands in later issues:
#
#   #11  — auth (Cognito user pool + JWT authorizer on the routes below)
#   #12  — DynamoDB tables (recipes, plans, grocery lists) + IAM grants on the exec role
#   #14  — recipes CRUD Lambdas + routes
#   #15  — meal-plan CRUD Lambdas + routes
#   #16  — grocery-list Lambdas + routes
#
# Add new resources by concern in their own files (recipes.tf, plans.tf, auth.tf, ...) and extend the
# local.handlers / local.routes maps — do NOT introduce child modules.
# ===================================================================================================

# --- Lambda packaging -----------------------------------------------------------------------------
# A single zip over the pre-built dist dir (backend/build.sh vendors deps into it). Every function
# shares the bundle and selects its entrypoint via the `handler` string, keyed off local.handlers.
data "archive_file" "api" {
  type        = "zip"
  source_dir  = var.lambda_dist_dir
  output_path = "${path.module}/.build/api.zip"
}

# --- Lambda execution role ------------------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name = "recipe-api-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# CloudWatch Logs (create log group + put events) for every function.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# TODO(#12): attach a recipe-api-access inline policy granting dynamodb:* on the recipes / plans /
# grocery tables once they exist. The hello handler needs no extra permissions today.

# --- Lambdas --------------------------------------------------------------------------------------
locals {
  lambda_env = {
    # TODO(#12): inject table names here, e.g. RECIPES_TABLE = aws_dynamodb_table.recipes.name
    STAGE = "shared"
  }

  # Map of logical function name -> handler entrypoint ("<module>.<function>"). Extend per issue.
  handlers = {
    hello = "hello.handler"
  }
}

resource "aws_lambda_function" "api" {
  for_each         = local.handlers
  function_name    = "recipe-${replace(each.key, "_", "-")}"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = each.value
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  timeout          = 10

  environment {
    variables = local.lambda_env
  }
}

# Explicit log group per function so retention is managed (and the group exists before first invoke).
resource "aws_cloudwatch_log_group" "api" {
  for_each          = local.handlers
  name              = "/aws/lambda/${aws_lambda_function.api[each.key].function_name}"
  retention_in_days = 14
}

# --- HTTP API (API Gateway v2) --------------------------------------------------------------------
resource "aws_apigatewayv2_api" "http" {
  name          = "recipe-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
  }
}

# TODO(#11): add an aws_apigatewayv2_authorizer (JWT) wired to the Cognito user pool, then flip the
# auth routes below to authorization_type = "JWT".

resource "aws_apigatewayv2_integration" "api" {
  for_each               = local.handlers
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api[each.key].invoke_arn
  payload_format_version = "2.0"
}

locals {
  # Map of logical name -> route. `auth` is a placeholder until the #11 JWT authorizer exists.
  routes = {
    hello = { key = "GET /hello", auth = false }
    # TODO(#14-#16): GET/POST/PUT/DELETE /recipes, /plans, /grocery — auth = true once #11 lands.
  }
}

resource "aws_apigatewayv2_route" "api" {
  for_each  = local.routes
  api_id    = aws_apigatewayv2_api.http.id
  route_key = each.value.key
  target    = "integrations/${aws_apigatewayv2_integration.api[each.key].id}"
  # TODO(#11): authorization_type = each.value.auth ? "JWT" : "NONE" (+ authorizer_id).
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api" {
  for_each      = local.handlers
  statement_id  = "AllowApiGwInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
