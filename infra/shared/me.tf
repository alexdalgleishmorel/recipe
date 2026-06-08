# ===================================================================================================
# User profile + entitlements (#13). One Lambda (the `me` handler) backs both routes; it dispatches on
# the HTTP method. This file only declares the handler and the routes — packaging, the exec role/IAM,
# the integration, the log group, and lambda permission are all driven generically off local.handlers
# / local.routes in main.tf, so adding the surface is just these two maps. Copies recipes.tf with the
# /me paths. The profile is lazy-created on the first GET /me (the Cognito post-confirmation trigger
# is deferred to #11), and ADMIN_EMAIL (from var.admin_email, set in main.tf's lambda_env) decides the
# isAdmin flag at creation.
#
# TODO(#11): once the Cognito JWT authorizer exists, flip these routes to auth = true and have main.tf
# attach authorizer_id (the me handler already scopes to the JWT `sub`/`email` via common.get_user_id
# / common.get_user_email — the dev x-user-id / x-user-email fallbacks go away then).
# ===================================================================================================

locals {
  # Logical function name -> handler entrypoint, merged into local.handlers (main.tf).
  me_handlers = {
    me = "me.handler"
  }

  # Logical route name -> { route key, backing handler, auth flag }, merged into local.routes.
  me_routes = {
    me_get    = { key = "GET /me", integration = "me", auth = true }
    me_update = { key = "PUT /me", integration = "me", auth = true }
  }
}
