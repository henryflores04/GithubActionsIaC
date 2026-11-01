terraform {
  # Backend remoto del estado.
  #
  # El bloque debe existir aunque este vacio: los valores concretos llegan por
  # -backend-config. Sin este bloque, Terraform ignora esos parametros, usa
  # estado LOCAL dentro del runner y cada ejecucion del workflow empieza desde
  # cero, creando recursos duplicados en AWS.
  backend "s3" {}

  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}
