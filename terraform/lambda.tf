# ── Codigo de la funcion ───────────────────────────────────────────────
# Terraform comprime la carpeta src/ en cada plan, asi que el despliegue
# siempre usa el codigo actual.
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/lambda.zip"
}

# ── Log group ──────────────────────────────────────────────────────────
# Se crea explicitamente para fijar la retencion. Si se dejara que Lambda lo
# creara solo, la retencion seria infinita y los registros se acumularian.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-hello"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-hello"
  }
}

# ── Rol de ejecucion ───────────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-lambda-hello-role"
  description        = "Rol de ejecucion de la funcion hello del laboratorio"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${local.name_prefix}-lambda-hello-role"
  }
}

# Permiso minimo para escribir en CloudWatch Logs.
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Funcion ────────────────────────────────────────────────────────────
resource "aws_lambda_function" "hello" {
  function_name = "${local.name_prefix}-hello"
  description   = "Funcion de ejemplo protegida por Cognito y API Gateway"
  role          = aws_iam_role.lambda.arn

  runtime       = "nodejs20.x"
  handler       = "index.handler"
  architectures = ["x86_64"]

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_s

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      LAB_PREFIX  = var.project_prefix
    }
  }

  tags = {
    Name = "${local.name_prefix}-hello"
  }

  # Sin este depends_on, Terraform podria crear la funcion antes que su log
  # group y Lambda lo crearia sin retencion, haciendo fallar al de Terraform.
  depends_on = [aws_cloudwatch_log_group.lambda]
}

# ── Permiso de invocacion desde API Gateway ────────────────────────────
# Sin esta politica de recurso, API Gateway devuelve 500 sin escribir nada en
# el log de la Lambda, porque la funcion nunca llega a ejecutarse.
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
