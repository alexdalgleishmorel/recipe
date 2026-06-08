# ===================================================================================================
# Recipe image uploads (#17, #80). An S3 bucket holds recipe photos; the browser uploads bytes
# directly to S3 via a short-lived presigned PUT URL minted by the uploads Lambda (POST
# /uploads/presign), keeping image bytes off the API. The recipe stores the returned public URL in
# recipe.image.
#
# Objects are public-READ (so recipe.image renders in the browser) but writes are gated by the
# presigned PUT; the bucket is server-side encrypted, and a CORS rule lets the Pages origin PUT
# directly via the presigned URL. The exec role gets s3:PutObject/GetObject scoped to this bucket
# only. The handler + route plug into the generic local.handlers / local.routes maps in main.tf, and
# the bucket name is passed to the Lambda via lambda_env (UPLOADS_BUCKET, merged in main.tf).
#
# TODO(#11): once the Cognito JWT authorizer exists, flip the route to auth = true; identity already
# comes from common.get_user_id (the dev x-user-id fallback goes away then).
# ===================================================================================================

# bucket_prefix (not name) so the bucket name is globally unique across accounts/regions.
resource "aws_s3_bucket" "uploads" {
  bucket_prefix = "recipe-uploads-"
  force_destroy = true
}

# Objects are public-READ (recipe photos rendered via recipe.image URLs); writes stay gated by the
# presigned PUT. Block public ACLs (we use a bucket policy, not ACLs) but allow the public read
# policy below.
resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

# Public read for recipe images so a stored recipe.image URL renders in the browser. Keys are uuids
# (uploads/<userId>/<uuid>.<ext>), so objects aren't enumerable; uploads remain presign-gated.
resource "aws_s3_bucket_policy" "uploads_public_read" {
  bucket = aws_s3_bucket.uploads.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadRecipeImages"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.uploads.arn}/*"
    }]
  })
  # The public-access-block must allow public policies before this one applies.
  depends_on = [aws_s3_bucket_public_access_block.uploads]
}

# Server-side encryption at rest (SSE-S3 / AES256).
resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Allow the browser to PUT directly to the presigned URL from the Pages origin (reuses the API's
# allowed-origins var) and to read the ETag back after upload.
resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  cors_rule {
    allowed_methods = ["PUT", "GET"]
    allowed_origins = var.cors_allowed_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Grant the Lambda exec role object-level access scoped to this bucket only (no service wildcard).
resource "aws_iam_role_policy" "lambda_s3" {
  name = "recipe-api-uploads"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
      ]
      Resource = "${aws_s3_bucket.uploads.arn}/*"
    }]
  })
}

locals {
  # Logical function name -> handler entrypoint, merged into local.handlers (main.tf).
  uploads_handlers = {
    uploads = "uploads.handler"
  }

  # Logical route name -> { route key, backing handler, auth flag }, merged into local.routes.
  uploads_routes = {
    uploads_presign = { key = "POST /uploads/presign", integration = "uploads", auth = true }
  }
}
