variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "lambda_dist_dir" {
  description = "Pre-built Lambda dist dir (deps vendored) — produced by backend/build.sh before apply."
  type        = string
  default     = "../../backend/dist"
}

variable "cors_allowed_origins" {
  description = "Origins allowed to call the API (browser CORS). Defaults to the GitHub Pages site."
  type        = list(string)
  default     = ["https://alexdalgleishmorel.github.io"]
}

variable "admin_email" {
  description = "Email granted admin entitlements (isAdmin) when its profile is lazy-created (#13)."
  type        = string
  default     = "alex.dalgleishmorel@gmail.com"
}
