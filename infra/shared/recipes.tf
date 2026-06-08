# ===================================================================================================
# Recipes CRUD (#14). One Lambda (the `recipes` handler) backs all five routes; it dispatches on the
# HTTP method + the presence of the {id} path parameter. This file only declares the handler and the
# routes — packaging, the exec role/IAM, the integration, the log group, and lambda permission are all
# driven generically off local.handlers / local.routes in main.tf, so adding an entity is just these
# two maps. #15 (plans) and #16 (collections) copy this file verbatim with their own paths.
#
# TODO(#11): once the Cognito JWT authorizer exists, flip these routes to auth = true and have
# main.tf attach authorizer_id (the recipes handler already scopes every op to the JWT `sub` via
# common.get_user_id — the dev x-user-id / DEV_USER_ID fallback goes away then).
# ===================================================================================================

locals {
  # Logical function name -> handler entrypoint, merged into local.handlers (main.tf).
  recipes_handlers = {
    recipes = "recipes.handler"
  }

  # Logical route name -> { route key, backing handler, auth flag }, merged into local.routes.
  recipes_routes = {
    recipes_list   = { key = "GET /recipes", integration = "recipes", auth = true }
    recipes_create = { key = "POST /recipes", integration = "recipes", auth = true }
    recipes_get    = { key = "GET /recipes/{id}", integration = "recipes", auth = true }
    recipes_update = { key = "PUT /recipes/{id}", integration = "recipes", auth = true }
    recipes_delete = { key = "DELETE /recipes/{id}", integration = "recipes", auth = true }
  }
}
