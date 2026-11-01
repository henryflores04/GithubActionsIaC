locals {
  api_base = trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")
}

output "api_base_url" {
  description = "URL base de la API (el stage $default no aparece en la ruta)"
  value       = local.api_base
}

output "api_hello_url" {
  description = "Ruta protegida. Requiere un access token de Cognito en el header Authorization"
  value       = "${local.api_base}/hello"
}

output "api_health_url" {
  description = "Ruta publica, util para comprobar que la API responde"
  value       = "${local.api_base}/health"
}

output "cognito_user_pool_id" {
  description = "ID del User Pool"
  value       = aws_cognito_user_pool.this.id
}

output "cognito_client_id" {
  description = "Client ID usado como audience del autorizador JWT"
  value       = aws_cognito_user_pool_client.this.id
}

output "cognito_issuer" {
  description = "Issuer del JWT que valida API Gateway"
  value       = "https://${aws_cognito_user_pool.this.endpoint}"
}

output "lambda_function_name" {
  description = "Nombre de la funcion Lambda"
  value       = aws_lambda_function.hello.function_name
}

output "aws_account_id" {
  description = "Cuenta de AWS donde quedo desplegado el laboratorio"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Region del despliegue"
  value       = var.aws_region
}
