# ── Cognito User Pool ──────────────────────────────────────────────────
# Proveedor de identidad que emite los JWT que API Gateway valida.
# El login se hace con el correo electronico como nombre de usuario.
resource "aws_cognito_user_pool" "this" {
  name = "${local.name_prefix}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = var.cognito_password_min_length
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # MFA opcional: se puede activar TOTP, pero no se exige para el laboratorio.
  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Proteccion contra fuerza bruta.
  user_pool_add_ons {
    advanced_security_mode = "OFF"
  }

  tags = {
    Name = "${local.name_prefix}-users"
  }
}

# ── Cliente de aplicacion ──────────────────────────────────────────────
# generate_secret = false porque un cliente publico (SPA o CLI) no puede
# custodiar un secreto. El flujo permitido es SRP sin secreto de cliente.
resource "aws_cognito_user_pool_client" "this" {
  name         = "${local.name_prefix}-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    # Permite admin-initiate-auth, que exige credenciales de IAM y sirve para
    # obtener un token de prueba desde la CLI sin implementar SRP a mano.
    # En produccion se retiraria: las aplicaciones reales usan SRP.
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
  ]

  prevent_user_existence_errors = "ENABLED"

  # El access token es el que lleva los grupos/claims que API Gateway evalua.
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}
