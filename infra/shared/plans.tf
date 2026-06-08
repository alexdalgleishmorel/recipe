# ===================================================================================================
# Meal-plan CRUD (#15). One Lambda (the `plans` handler) backs all five routes; it dispatches on the
# HTTP method + the presence of the {id} path parameter. This file only declares the handler and the
# routes — packaging, the exec role/IAM, the integration, the log group, and lambda permission are all
# driven generically off local.handlers / local.routes in main.tf, so adding an entity is just these
# two maps. Copies recipes.tf verbatim with the /plans paths.
#
# TODO(#11): once the Cognito JWT authorizer exists, flip these routes to auth = true and have
# main.tf attach authorizer_id (the plans handler already scopes every op to the JWT `sub` via
# common.get_user_id — the dev x-user-id / DEV_USER_ID fallback goes away then).
# ===================================================================================================

locals {
  # Logical function name -> handler entrypoint, merged into local.handlers (main.tf).
  plans_handlers = {
    plans = "plans.handler"
  }

  # Logical route name -> { route key, backing handler, auth flag }, merged into local.routes.
  plans_routes = {
    plans_list   = { key = "GET /plans", integration = "plans", auth = true }
    plans_create = { key = "POST /plans", integration = "plans", auth = true }
    plans_get    = { key = "GET /plans/{id}", integration = "plans", auth = true }
    plans_update = { key = "PUT /plans/{id}", integration = "plans", auth = true }
    plans_delete = { key = "DELETE /plans/{id}", integration = "plans", auth = true }
  }
}
