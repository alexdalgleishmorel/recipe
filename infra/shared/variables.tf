variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "lambda_dist_dir" {
  description = "Pre-built Lambda dist dir (deps vendored) — produced by backend/build.sh before apply."
  type        = string
  default     = "../../backend/dist"
}
