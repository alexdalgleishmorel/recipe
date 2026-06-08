# ===================================================================================================
# AI recipe import (#19). One Lambda (the `import_recipe` handler) backs POST /recipes/import; it
# parses an uploaded recipe photo or PDF into a structured Recipe draft by calling the Anthropic API
# directly (NOT Bedrock). Packaging, the exec role, the integration, the log group, and the lambda
# permission are all driven generically off local.handlers / local.routes in main.tf, so this file
# only declares the handler, the route, and the one extra IAM grant the function needs.
#
# The Anthropic API key lives in AWS Secrets Manager (secret name "recipe/anthropic-api-key"); the
# handler reads it at runtime via boto3 and caches it. The exec role is granted
# secretsmanager:GetSecretValue on that secret only (wildcard suffix covers Secrets Manager's random
# 6-char suffix). The optional {key} path that fetches the uploaded file from S3 reuses the
# s3:GetObject grant already attached to the role by #17 (uploads.tf), and the bucket name reuses the
# UPLOADS_BUCKET env var merged into lambda_env in main.tf — no extra wiring here.
#
# The route is auth = true (the Cognito JWT authorizer from #11); identity comes from
# common.get_user_id and the canAiImport gate is enforced in the handler via the users DAL.
# ===================================================================================================

# Grant the Lambda exec role read access to the Anthropic API key secret only (no service wildcard).
# The "-*" suffix matches Secrets Manager's auto-appended 6-character random suffix on the ARN.
resource "aws_iam_role_policy" "lambda_secrets" {
  name = "recipe-api-anthropic-secret"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:us-east-1:696532327395:secret:recipe/anthropic-api-key-*"
    }]
  })
}

locals {
  # Logical function name -> handler entrypoint, merged into local.handlers (main.tf).
  import_recipe_handlers = {
    import_recipe = "import_recipe.handler"
  }

  # Logical route name -> { route key, backing handler, auth flag }, merged into local.routes. Both
  # the import POST and the batch-status GET are served by the one import_recipe Lambda (it dispatches
  # on method + the {id} path parameter), so no extra integration is needed.
  import_recipe_routes = {
    recipes_import       = { key = "POST /recipes/import", integration = "import_recipe", auth = true }
    recipes_import_batch = { key = "GET /recipes/import/batch/{id}", integration = "import_recipe", auth = true }
  }
}
