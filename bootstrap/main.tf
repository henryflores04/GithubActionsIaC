data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Subject OIDC al que se limita el rol.
  #   - Formato con IDs inmutables (recomendado para repositorios nuevos):
  #     repo:OWNER@OWNER_ID/REPO@REPO_ID:environment:dev
  #   - Formato heredado:
  #     repo:OWNER/REPO:environment:dev
  oidc_subject = var.use_immutable_subject ? (
    "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:environment:${var.environment}"
  ) : "repo:${var.github_owner}/${var.github_repo}:environment:${var.environment}"

  state_bucket_arn = aws_s3_bucket.state.arn
  state_object_arns = [
    "${local.state_bucket_arn}/${var.state_key_prefix}/terraform.tfstate",
    "${local.state_bucket_arn}/${var.state_key_prefix}/terraform.tfstate.tflock",
    "${local.state_bucket_arn}/${var.state_key_prefix}/terraform.tfstate.backup",
  ]

  lambda_role_arn   = "arn:aws:iam::${local.account_id}:role/${var.project_prefix}-${var.environment}-lambda-*"
  lambda_arn_prefix = "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${var.project_prefix}-${var.environment}-*"

  common_tags = {
    Project     = "github-actions-iac"
    Lab         = var.project_prefix
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ── Bucket S3 para el estado remoto de Terraform ───────────────────────
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  tags = merge(local.common_tags, {
    Name = var.state_bucket_name
    Role = "terraform-state"
  })
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ── Proveedor OIDC de GitHub ───────────────────────────────────────────
# El atributo thumbprint_list se omite a proposito: AWS gestiona los
# thumbprints del proveedor desde 2024. Si tu version del provider los exige,
# agrega:
#   thumbprint_list = [
#     "6938fd4d98bab03faadb97b34396831e3780aea1",
#     "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
#   ]
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-github-oidc"
  })
}

# ── Politica de confianza del rol de despliegue ────────────────────────
data "aws_iam_policy_document" "trust" {
  statement {
    sid    = "AllowGitHubActionsOIDC"
    effect = "Allow"

    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Sin comodines: solo el repositorio y el entorno exactos.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.oidc_subject]
    }
  }
}

# ── Politica de permisos del rol ───────────────────────────────────────
# Politica administrada por el cliente (no AdministratorAccess), limitada a
# los servicios del stack y al backend de estado.
data "aws_iam_policy_document" "deploy" {
  # --- Backend de estado: lectura del bucket, limitada al prefijo ---
  statement {
    sid    = "TerraformStateBucketList"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketLocation",
    ]

    resources = [local.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        var.state_key_prefix,
        "${var.state_key_prefix}/*",
      ]
    }
  }

  # --- Backend de estado: solo el tfstate y su lockfile ---
  statement {
    sid    = "TerraformStateObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = local.state_object_arns
  }

  # --- Cognito User Pools ---
  statement {
    sid    = "CognitoUserPools"
    effect = "Allow"

    actions = [
      "cognito-idp:CreateUserPool",
      "cognito-idp:DeleteUserPool",
      "cognito-idp:DescribeUserPool",
      "cognito-idp:UpdateUserPool",
      "cognito-idp:ListUserPools",
      "cognito-idp:GetUserPoolMfaConfig",
      "cognito-idp:SetUserPoolMfaConfig",
      "cognito-idp:CreateUserPoolClient",
      "cognito-idp:DeleteUserPoolClient",
      "cognito-idp:DescribeUserPoolClient",
      "cognito-idp:UpdateUserPoolClient",
      "cognito-idp:ListUserPoolClients",
      "cognito-idp:TagResource",
      "cognito-idp:UntagResource",
      "cognito-idp:ListTagsForResource",
    ]

    # CreateUserPool no admite restriccion por ARN porque el ID aun no existe.
    resources = ["*"]
  }

  # --- API Gateway (HTTP API v2) ---
  statement {
    sid    = "ApiGatewayV2"
    effect = "Allow"

    actions = [
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:PATCH",
      "apigateway:DELETE",
    ]

    resources = [
      "arn:aws:apigateway:${var.aws_region}::/apis",
      "arn:aws:apigateway:${var.aws_region}::/apis/*",
      "arn:aws:apigateway:${var.aws_region}::/tags",
      "arn:aws:apigateway:${var.aws_region}::/tags/*",
    ]
  }

  # --- Lambda ---
  statement {
    sid    = "LambdaFunctions"
    effect = "Allow"

    actions = [
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:ListFunctions",
      "lambda:ListVersionsByFunction",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:ListTags",
    ]

    resources = [local.lambda_arn_prefix]
  }

  # --- CloudWatch Logs de los recursos del laboratorio ---
  statement {
    sid    = "LogsLogGroups"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource",
      "logs:TagLogGroup",
      "logs:UntagLogGroup",
      "logs:ListTagsLogGroup",
    ]

    resources = [
      "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_prefix}-${var.environment}-*",
      "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_prefix}-${var.environment}-*:*",
      "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/apigateway/${var.project_prefix}-${var.environment}-*",
      "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/apigateway/${var.project_prefix}-${var.environment}-*:*",
    ]
  }

  # DescribeLogGroups y las politicas de recurso no admiten restriccion por ARN.
  statement {
    sid    = "LogsAccountLevel"
    effect = "Allow"

    actions = [
      "logs:DescribeLogGroups",
      "logs:PutResourcePolicy",
      "logs:DeleteResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]

    resources = ["*"]
  }

  # --- Roles IAM de ejecucion de Lambda ---
  statement {
    sid    = "LambdaExecutionRoles"
    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
    ]

    resources = [local.lambda_role_arn]
  }

  # Solo se puede pasar el rol de ejecucion de Lambda, y solo a Lambda.
  statement {
    sid    = "PassLambdaExecutionRole"
    effect = "Allow"

    actions   = ["iam:PassRole"]
    resources = [local.lambda_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  # Terraform consulta la identidad para componer ARNs.
  statement {
    sid       = "CallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deploy" {
  name        = "${var.project_prefix}-github-actions-deploy"
  description = "Permisos acotados para desplegar el stack del laboratorio desde GitHub Actions"
  policy      = data.aws_iam_policy_document.deploy.json

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-github-actions-deploy"
  })
}

# ── Rol de despliegue ──────────────────────────────────────────────────
resource "aws_iam_role" "deploy" {
  name                 = "${var.project_prefix}-github-actions-${var.environment}"
  description          = "Rol asumido por GitHub Actions mediante OIDC para desplegar en ${var.environment}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name = "${var.project_prefix}-github-actions-${var.environment}"
  })
}

resource "aws_iam_role_policy_attachment" "deploy" {
  role       = aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy.arn
}
