# Configuracion del provider de AWS.
#
# Las credenciales NUNCA se declaran aqui: en GitHub Actions las inyecta
# aws-actions/configure-aws-credentials a partir del rol asumido por OIDC, y en
# local se toman del perfil configurado con `aws configure` o AWS_PROFILE.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Necesario para componer ARNs que incluyen el ID de cuenta (rol de Lambda,
# politicas de registros) sin escribirlo a mano en el codigo.
data "aws_caller_identity" "current" {}
