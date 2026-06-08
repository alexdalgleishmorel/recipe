data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ===================================================================================================
# This root is the app stack. Today it stands up a single "hello" Lambda behind an HTTP API to prove
# the packaging + integration pattern end to end. The real surface area lands in later issues:
#
#   #11  — auth (Cognito user pool + JWT authorizer on the routes below)
#   #12  — DynamoDB tables (recipes, plans, collections, users, shares) + IAM grants  [DONE: tables.tf]
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

# DynamoDB data access (#12): grant the exec role item-level ops on each entity table and its indexes.
# Scoped to exactly the recipe-* table arns (+ /index/* for the GSIs) — no wildcard on the service.
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "recipe-api-access"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
        "dynamodb:BatchGetItem",
        "dynamodb:BatchWriteItem",
      ]
      Resource = flatten([
        for t in [
          aws_dynamodb_table.recipes,
          aws_dynamodb_table.meal_plans,
          aws_dynamodb_table.collections,
          aws_dynamodb_table.users,
          aws_dynamodb_table.shares,
        ] : [t.arn, "${t.arn}/index/*"]
      ])
    }]
  })
}

# --- Lambdas --------------------------------------------------------------------------------------
locals {
  lambda_env = {
    STAGE             = "shared"
    RECIPES_TABLE     = aws_dynamodb_table.recipes.name
    MEAL_PLANS_TABLE  = aws_dynamodb_table.meal_plans.name
    COLLECTIONS_TABLE = aws_dynamodb_table.collections.name
    USERS_TABLE       = aws_dynamodb_table.users.name
    SHARES_TABLE      = aws_dynamodb_table.shares.name
  }

  # Map of logical function name -> handler entrypoint ("<module>.<function>"). Extend per issue by
  # merging in the issue's own map (defined in its own file, e.g. recipes.tf) — keep this block lean.
  handlers = merge(
    {
      hello = "hello.handler"
    },
    local.recipes_handlers,
    local.plans_handlers,
    local.collections_handlers,
  )
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
    allow_origins = var.cors_allowed_origins
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    # x-user-id is the dev-identity header (until the Cognito JWT authorizer in #11);
    # authorization carries the bearer JWT afterward.
    allow_headers = ["content-type", "authorization", "x-user-id"]
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
  # `integration` names the handler (local.handlers key) that backs the route, so several routes can
  # share one Lambda (the recipes handler dispatches all five recipe routes). Extend per issue by
  # merging in the issue's own map (its own file, e.g. recipes.tf) — keep this block lean.
  routes = merge(
    {
      hello = { key = "GET /hello", integration = "hello", auth = false }
    },
    local.recipes_routes,
    local.plans_routes,
    local.collections_routes,
  )
}

resource "aws_apigatewayv2_route" "api" {
  for_each  = local.routes
  api_id    = aws_apigatewayv2_api.http.id
  route_key = each.value.key
  # Routes name the handler they hit via `integration`, so several routes can share one Lambda
  # (e.g. all five recipe routes -> the recipes integration).
  target = "integrations/${aws_apigatewayv2_integration.api[each.value.integration].id}"
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
