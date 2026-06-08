# ===================================================================================================
# Admin entitlements (#20). One Lambda (the `admin` handler) backs the admin route. This file only
# declares the handler and the route — packaging, the exec role/IAM, the integration, the log group,
# and lambda permission are all driven generically off local.handlers / local.routes in main.tf, so
# adding the surface is just these two maps. Copies me.tf with the /admin path.
#
# POST /admin/entitlements { userId, canAiImport } flips a target user's canAiImport. The handler
# reads the caller's stored isAdmin (via the users DAL) and rejects non-admins with 403; the owner
# (ADMIN_EMAIL) is bootstrapped as admin by #13's lazy-create, so no separate bootstrap is needed.
#
# TODO(#11): once the Cognito JWT authorizer exists, flip this route to auth = true and have main.tf
# attach authorizer_id (the admin handler already scopes to the JWT `sub` via common.get_user_id —
# the dev x-user-id fallback goes away then). The route is not blocked on #11.
# ===================================================================================================

locals {
  # Logical function name -> handler entrypoint, merged into local.handlers (main.tf).
  admin_handlers = {
    admin = "admin.handler"
  }

  # Logical route name -> { route key, backing handler, auth flag }, merged into local.routes.
  # Both routes hit the one `admin` handler, which dispatches on method+path and gates every route on
  # the caller's stored isAdmin (403 otherwise).
  admin_routes = {
    admin_entitlements = { key = "POST /admin/entitlements", integration = "admin", auth = true }
    # GET /admin/users lists all users for the entitlement UI (#65); Scan grant added in main.tf.
    admin_users = { key = "GET /admin/users", integration = "admin", auth = true }
  }
}
