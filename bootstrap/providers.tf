# Configuracion del provider de AWS para el bootstrap.
#
# Sin este bloque el provider no tiene region declarada y toma la del perfil
# del CLI, que puede ser distinta de la del laboratorio. Eso hacia que el
# bucket de estado se creara en otra region que el resto del stack.
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
