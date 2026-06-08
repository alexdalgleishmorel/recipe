# ===================================================================================================
# Auth (#11): Cognito user pool federated to Google (the sole IdP — Apple was dropped, no passwords),
# its Hosted UI domain + public SPA app client (OAuth2 auth-code + PKCE), and the API Gateway v2 JWT
# authorizer that protects every app route. The frontend drives the Hosted UI, then sends the Cognito
# ID token as `Authorization: Bearer <jwt>`; API Gateway verifies it and exposes the claims at
# requestContext.authorizer.jwt.claims, where `sub` is the stable user id (common.get_user_id).
#
# Route wiring lives in main.tf: aws_apigatewayv2_route.api flips each route to JWT when its
# local.routes entry has auth = true (hello stays NONE).
# ===================================================================================================

# --- User pool ------------------------------------------------------------------------------------
# Email is the username/sign-in attribute; email + name are the standard attributes we mirror from
# Google. Sign-up is federated only (no passwords), so the password policy is largely vestigial.
resource "aws_cognito_user_pool" "users" {
  name                     = "recipe-users-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    required            = false
    mutable             = true
    string_attribute_constraints {
      min_length = 0
      max_length = 256
    }
  }
}

# --- Google identity provider ---------------------------------------------------------------------
# Client id/secret arrive as sensitive TF_VARs from CI (never committed). Attribute mapping pulls the
# Google profile fields onto the Cognito user: email->email, name->name, and the Cognito username from
# the federated subject identifier so it is stable per Google account.
resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.users.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
  }

  attribute_mapping = {
    email    = "email"
    name     = "name"
    username = "sub"
  }
}

# --- Hosted UI domain -------------------------------------------------------------------------------
# The prefix is fixed: the owner already registered
# https://recipe-app-696532327395.auth.us-east-1.amazoncognito.com/oauth2/idpresponse as the Google
# OAuth redirect URI, so this MUST match exactly.
resource "aws_cognito_user_pool_domain" "hosted_ui" {
  domain       = "recipe-app-696532327395"
  user_pool_id = aws_cognito_user_pool.users.id
}

# --- App client (public SPA) ----------------------------------------------------------------------
# No client secret (browser/PKCE), authorization-code flow only, Google as the sole IdP. Callback /
# logout URLs cover the deployed GitHub Pages origin plus local dev ports (Cognito does not allow
# wildcard localhost, so list the concrete dev ports).
resource "aws_cognito_user_pool_client" "spa" {
  name         = "recipe-web"
  user_pool_id = aws_cognito_user_pool.users.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["Google"]

  callback_urls = [
    "https://alexdalgleishmorel.github.io/recipes/",
    "https://alexdalgleishmorel.github.io/recipe/",
    "http://localhost:8080/",
    "http://localhost:3000/",
  ]
  logout_urls = [
    "https://alexdalgleishmorel.github.io/recipes/",
    "https://alexdalgleishmorel.github.io/recipe/",
    "http://localhost:8080/",
    "http://localhost:3000/",
  ]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  # The Google IdP must exist before the client can list it in supported_identity_providers.
  depends_on = [aws_cognito_identity_provider.google]
}

# --- API Gateway v2 JWT authorizer ----------------------------------------------------------------
# Verifies the bearer token in the Authorization header against the Cognito user pool. The frontend
# sends the ID token, whose `aud` equals the app client id (the access token's audience differs), so
# the audience list is the client id.
resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  name             = "cognito-jwt"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.users.id}"
    audience = [aws_cognito_user_pool_client.spa.id]
  }
}
