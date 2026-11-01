terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Sin bloque backend: el bootstrap usa estado LOCAL.
  # Se ejecuta una sola vez con un usuario administrador para crear el bucket
  # de estado, el proveedor OIDC y el rol de despliegue. A partir de ahi,
  # Terraform ya puede usar el backend S3 remoto.
}
