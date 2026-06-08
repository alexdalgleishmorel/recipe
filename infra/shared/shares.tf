# ===================================================================================================
# Sharing (#18) — fork-share (editable COPY) of recipes and collections. One Lambda (the `shares`
# handler) backs all routes; it dispatches on the HTTP method + path params ({token} / {idOrToken}).
# This file only declares the handler and the routes — packaging, the exec role/IAM, the integration,
# the log group, and lambda permission are all driven generically off local.handlers / local.routes
# in main.tf (merged there, append-only). Mirrors recipes.tf / collections.tf.
#
# Routes:
#   POST /shares                   — create a share (snapshot the item; email or link target)
#   GET  /shares/incoming          — shares targeted at the caller (literal beats {token})
#   GET  /shares/{token}           — preview a link share (the snapshot's display metadata)
#   POST /shares/{idOrToken}/claim — deep-copy the snapshot into the caller's library with new ids
#
# TODO(#11): once the Cognito JWT authorizer exists, flip the authenticated routes to auth = true and
# have main.tf attach authorizer_id (the handler already scopes every op to the JWT `sub` via
# common.get_user_id — the dev x-user-id / DEV_USER_ID fallback goes away then). GET /shares/{token}
# is the link-preview route and is intentionally left auth = false so an unauthenticated recipient can
# see what a link offers before signing in to claim it.
# ===================================================================================================

locals {
  # Logical function name -> handler entrypoint, merged into local.handlers (main.tf).
  shares_handlers = {
    shares = "shares.handler"
  }

  # Logical route name -> { route key, backing handler, auth flag }, merged into local.routes.
  # `incoming` is a literal segment so API Gateway v2 matches it ahead of the {token} variable route.
  shares_routes = {
    shares_create   = { key = "POST /shares", integration = "shares", auth = true }
    shares_incoming = { key = "GET /shares/incoming", integration = "shares", auth = true }
    shares_preview  = { key = "GET /shares/{token}", integration = "shares", auth = false }
    shares_claim    = { key = "POST /shares/{idOrToken}/claim", integration = "shares", auth = true }
  }
}
