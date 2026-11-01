provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "github-actions-iac"
      Lab         = var.project_prefix
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
