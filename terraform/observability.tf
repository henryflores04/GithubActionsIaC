# ── Log group de API Gateway ───────────────────────────────────────────
# Destino de los access logs configurados en el stage de apigateway.tf.
resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${local.name_prefix}-api"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

# ── Politica de recurso para los logs ──────────────────────────────────
# API Gateway necesita permiso explicito para escribir en el log group. Sin
# esta politica el despliegue del stage falla o los access logs quedan vacios.
resource "aws_cloudwatch_log_resource_policy" "apigw" {
  policy_name = "${local.name_prefix}-apigw-logs"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAPIGatewayWriteLogs"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "${aws_cloudwatch_log_group.apigw.arn}:*"
      }
    ]
  })
}

# ── Log group de la Lambda ─────────────────────────────────────────────
# Se declara en lambda.tf porque alli se usa el depends_on de la funcion.
# Se deja constancia aqui en un comentario para no duplicar el recurso.
