# ===================================================================================================
# DynamoDB tables (#12). Persistence is partitioned by userId: every item carries the owner's id as
# the partition key (PK = userId) and the entity id as the sort key (SK = entityId). This keeps a
# user's whole library on one partition (cheap, consistent Query per entity type) and makes per-user
# isolation the default — a Query is always scoped to a single userId.
#
# Sharing uses fork-copy (a share materializes a *copy* of the entity under the recipient's userId),
# so there is no cross-user read path to model here. Two lookups, however, are not keyed by userId:
#
#   * email lookup  — resolve a User by email to share-by-email (User.email_index GSI)
#   * token lookup  — resolve a Share by its opaque link token (Share.token_index GSI)
#
# One table per entity (vs. single-table) keeps the access layer and IAM grants legible: each table
# gets dynamodb:* on exactly its own arn (+ its index/*). PAY_PER_REQUEST throughout — traffic is
# spiky and low-volume, so on-demand avoids capacity planning. default_tags (provider, versions.tf)
# tag every table automatically.
# ===================================================================================================

locals {
  # Shared key schema for the owner-partitioned entity tables.
  entity_hash_key  = "userId"
  entity_range_key = "entityId"
}

# --- Recipe ---------------------------------------------------------------------------------------
resource "aws_dynamodb_table" "recipes" {
  name         = "recipe-recipes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = local.entity_hash_key
  range_key    = local.entity_range_key

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "entityId"
    type = "S"
  }
}

# --- MealPlan -------------------------------------------------------------------------------------
resource "aws_dynamodb_table" "meal_plans" {
  name         = "recipe-meal-plans"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = local.entity_hash_key
  range_key    = local.entity_range_key

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "entityId"
    type = "S"
  }
}

# --- Collection -----------------------------------------------------------------------------------
resource "aws_dynamodb_table" "collections" {
  name         = "recipe-collections"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = local.entity_hash_key
  range_key    = local.entity_range_key

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "entityId"
    type = "S"
  }
}

# --- User -----------------------------------------------------------------------------------------
# Stored userId == entityId (one item per user). The email_index GSI resolves a User by email for
# share-by-email; email is unique per user and the projection is ALL so the lookup returns the row.
resource "aws_dynamodb_table" "users" {
  name         = "recipe-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = local.entity_hash_key
  range_key    = local.entity_range_key

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "entityId"
    type = "S"
  }
  attribute {
    name = "email"
    type = "S"
  }

  global_secondary_index {
    name            = "email_index"
    hash_key        = "email"
    projection_type = "ALL"
  }
}

# --- Share ----------------------------------------------------------------------------------------
# A Share row records a fork-copy invitation owned by the sharer (PK = sharer userId). Two non-owner
# lookups need GSIs:
#
#   * token_index          — resolve a Share by its opaque link token so a recipient can redeem a link
#                            share without knowing the owner.
#   * recipient_email_index — list the shares targeted at a recipient who has no row under their own
#                            userId yet (the sharer addressed them by email before they signed in, so
#                            /shares/incoming has to find pending shares by the caller's email).
#
# Tokens and emails are unique enough to identify; projection ALL returns the full share record (incl.
# the snapshot) on lookup.
resource "aws_dynamodb_table" "shares" {
  name         = "recipe-shares"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = local.entity_hash_key
  range_key    = local.entity_range_key

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "entityId"
    type = "S"
  }
  attribute {
    name = "token"
    type = "S"
  }
  attribute {
    name = "recipientEmail"
    type = "S"
  }

  global_secondary_index {
    name            = "token_index"
    hash_key        = "token"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "recipient_email_index"
    hash_key        = "recipientEmail"
    projection_type = "ALL"
  }
}
