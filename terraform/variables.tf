variable "aws_region" {
  description = "Region de AWS donde se despliega el laboratorio"
  type        = string
  default     = "us-east-2"
}

variable "project_prefix" {
  description = "Prefijo de laboratorio aplicado a todos los recursos"
  type        = string
  default     = "lab09"
}

variable "environment" {
  description = "Entorno logico. El laboratorio solo despliega en dev"
  type        = string
  default     = "dev"

  validation {
    condition     = var.environment == "dev"
    error_message = "Este laboratorio solo admite el entorno dev."
  }
}

variable "log_retention_days" {
  description = "Retencion de los log groups de CloudWatch"
  type        = number
  default     = 7
}

variable "lambda_memory_mb" {
  description = "Memoria de la funcion Lambda en MB"
  type        = number
  default     = 256
}

variable "lambda_timeout_s" {
  description = "Timeout de la funcion Lambda en segundos"
  type        = number
  default     = 10
}

variable "cognito_password_min_length" {
  description = "Longitud minima de contrasena exigida por el User Pool"
  type        = number
  default     = 12
}
