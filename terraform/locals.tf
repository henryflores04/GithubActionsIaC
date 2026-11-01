locals {
  name_prefix = "${var.project_prefix}-${var.environment}"

  common_tags = {
    Project     = "github-actions-iac"
    Lab         = var.project_prefix
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
