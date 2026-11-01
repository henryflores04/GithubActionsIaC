output "state_bucket_name" {
  description = "Valor para la variable TF_STATE_BUCKET de GitHub"
  value       = aws_s3_bucket.state.id
}

output "deploy_role_arn" {
  description = "Valor para la variable AWS_ROLE_ARN de GitHub"
  value       = aws_iam_role.deploy.arn
}

output "oidc_provider_arn" {
  description = "ARN del proveedor OIDC registrado"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "oidc_subject" {
  description = "Subject exacto al que esta limitada la politica de confianza"
  value       = local.oidc_subject
}

output "aws_account_id" {
  description = "Cuenta de AWS del laboratorio"
  value       = local.account_id
}

output "aws_region" {
  description = "Region del laboratorio (valor para AWS_REGION en GitHub)"
  value       = var.aws_region
}

output "resumen_para_github" {
  description = "Variables a cargar en Settings -> Secrets and variables -> Actions"
  value       = <<-EOT
    AWS_REGION       = ${var.aws_region}
    AWS_ROLE_ARN     = ${aws_iam_role.deploy.arn}
    TF_STATE_BUCKET  = ${aws_s3_bucket.state.id}
  EOT
}
