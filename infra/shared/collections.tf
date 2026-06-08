# ===================================================================================================
# Collection CRUD (#16). One Lambda (the `collections` handler) backs all five routes; it dispatches
# on the HTTP method + the presence of the {id} path parameter. This file only declares the handler
# and the routes — packaging, the exec role/IAM, the integration, the log group, and lambda permission
# are all driven generically off local.handlers / local.routes in main.tf, so adding an entity is just
# these two maps. Copies recipes.tf / plans.tf verbatim with the /collections paths.
#
# TODO(#11): once the Cognito JWT authorizer exists, flip these routes to auth = true and have
# main.tf attach authorizer_id (the collections handler already scopes every op to the JWT `sub` via
# common.get_user_id — the dev x-user-id / DEV_USER_ID fallback goes away then).
# ===================================================================================================

locals {
  # Logical function name -> handler entrypoint, merged into local.handlers (main.tf).
  collections_handlers = {
    collections = "collections.handler"
  }

  # Logical route name -> { route key, backing handler, auth flag }, merged into local.routes.
  collections_routes = {
    collections_list   = { key = "GET /collections", integration = "collections", auth = true }
    collections_create = { key = "POST /collections", integration = "collections", auth = true }
    collections_get    = { key = "GET /collections/{id}", integration = "collections", auth = true }
    collections_update = { key = "PUT /collections/{id}", integration = "collections", auth = true }
    collections_delete = { key = "DELETE /collections/{id}", integration = "collections", auth = true }
  }
}
