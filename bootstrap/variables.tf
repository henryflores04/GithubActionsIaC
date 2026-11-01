variable "aws_region" {
  description = "Region de AWS del laboratorio"
  type        = string
  default     = "us-east-2"
}

variable "project_prefix" {
  description = "Prefijo de laboratorio"
  type        = string
  default     = "lab09"
}

variable "environment" {
  description = "Entorno de GitHub Actions al que se limita el rol"
  type        = string
  default     = "dev"
}

variable "state_bucket_name" {
  description = "Nombre GLOBALMENTE UNICO del bucket S3 para el estado de Terraform"
  type        = string
}

variable "state_key_prefix" {
  description = "Prefijo de la clave del estado dentro del bucket"
  type        = string
  default     = "lab09/dev"
}

variable "github_owner" {
  description = "Propietario del repositorio en GitHub"
  type        = string
}

variable "github_repo" {
  description = "Nombre del repositorio en GitHub"
  type        = string
}

variable "use_immutable_subject" {
  description = "Usar el formato de subject con IDs inmutables (repositorios creados desde julio de 2026)"
  type        = bool
  default     = true
}

variable "github_owner_id" {
  description = "ID numerico del propietario en GitHub. Obligatorio si use_immutable_subject = true"
  type        = string
  default     = ""
}

variable "github_repo_id" {
  description = "ID numerico del repositorio en GitHub. Obligatorio si use_immutable_subject = true"
  type        = string
  default     = ""
}
