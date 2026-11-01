locals {
  # Prefijo comun de nombres: lab09-dev-...
  name_prefix = "${var.project_prefix}-${var.environment}"

  # Etiquetas aplicadas automaticamente a todos los recursos por default_tags.
  # Environment permite separar costos por entorno en Cost Explorer.
  common_tags = {
    Project     = "github-actions-iac"
    Lab         = var.project_prefix
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
