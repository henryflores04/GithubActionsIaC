# ── HTTP API ───────────────────────────────────────────────────────────
# Se usa HTTP API (v2) en lugar de REST API porque valida JWT de forma nativa
# con un autorizador JWT, es mas barato y tiene menor latencia.
resource "aws_apigatewayv2_api" "this" {
  name          = "${local.name_prefix}-api"
  description   = "API del laboratorio protegida con Cognito"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

# ── Autorizador JWT ────────────────────────────────────────────────────
# Valida la firma del token contra el issuer de Cognito y comprueba que el
# audience coincida con el client id del User Pool.
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "cognito-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.this.id]
    issuer   = "https://${aws_cognito_user_pool.this.endpoint}"
  }
}

# ── Integracion con Lambda ─────────────────────────────────────────────
resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.this.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.hello.invoke_arn

  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

# ── Ruta protegida ─────────────────────────────────────────────────────
# Exige un token valido de Cognito; sin el, API Gateway responde 401 y la
# funcion nunca se invoca.
resource "aws_apigatewayv2_route" "hello" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /hello"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# ── Ruta publica ───────────────────────────────────────────────────────
# Sirve para comprobar que la API responde sin token y contrastar con 401 de
# la ruta protegida.
resource "aws_apigatewayv2_route" "health" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /health"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "NONE"
}

# ── Stage por defecto ──────────────────────────────────────────────────
# El stage "$default" no aparece en la URL: la base queda como
# https://<api-id>.execute-api.<region>.amazonaws.com
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationErr = "$context.integration.error"
      authError      = "$context.authorizer.error"
    })
  }

  tags = {
    Name = "${local.name_prefix}-api-default"
  }
}
