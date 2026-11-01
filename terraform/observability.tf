resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${local.name_prefix}-api"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

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
