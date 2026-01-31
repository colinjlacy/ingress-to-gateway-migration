# AWS Cognito User Pool for OIDC authentication
# Used to demonstrate OIDC integration with Ingress-NGINX and Envoy Gateway

# Cognito User Pool
resource "aws_cognito_user_pool" "demo" {
  name = "${local.cluster_name}-user-pool"

  # Allow users to sign in with email
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # Email configuration (using Cognito default for demo)
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # User pool schema
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  tags = local.tags
}

# Cognito User Pool Domain (for hosted UI)
resource "aws_cognito_user_pool_domain" "demo" {
  domain       = "${lower(local.cluster_name)}-demo-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.demo.id
}

# Cognito User Pool Client for Ingress-NGINX (using oauth2-proxy)
resource "aws_cognito_user_pool_client" "ingress_nginx" {
  name         = "${local.cluster_name}-ingress-nginx-client"
  user_pool_id = aws_cognito_user_pool.demo.id

  # OAuth flows
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  # Callback URLs - update these with your actual domain
  callback_urls = [
    "https://nginx.colinjcodesalot.com/oauth2/callback",
    "http://localhost:4180/oauth2/callback" # For local testing
  ]

  logout_urls = [
    "https://nginx.colinjcodesalot.com/",
    "http://localhost:4180/"
  ]

  # Token validity
  access_token_validity  = 60  # minutes
  id_token_validity      = 60  # minutes
  refresh_token_validity = 30  # days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Generate client secret
  generate_secret = true

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Supported identity providers
  supported_identity_providers = ["COGNITO"]

  # Read and write attributes
  read_attributes = [
    "email",
    "email_verified",
    "name",
    "preferred_username"
  ]

  write_attributes = [
    "email",
    "name",
    "preferred_username"
  ]
}

# Cognito User Pool Client for Envoy Gateway
resource "aws_cognito_user_pool_client" "envoy_gateway" {
  name         = "${local.cluster_name}-envoy-gateway-client"
  user_pool_id = aws_cognito_user_pool.demo.id

  # OAuth flows
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  # Callback URLs for Envoy Gateway native OIDC
  callback_urls = [
    "https://gateway.colinjcodesalot.com/protected/oauth2/callback",
    "http://localhost:4180/oauth2/callback" # For local testing
  ]

  logout_urls = [
    "https://gateway.colinjcodesalot.com/protected/logout",
    "http://localhost:4180/"
  ]

  # Token validity
  access_token_validity  = 60  # minutes
  id_token_validity      = 60  # minutes
  refresh_token_validity = 30  # days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Generate client secret
  generate_secret = true

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Supported identity providers
  supported_identity_providers = ["COGNITO"]

  # Read and write attributes
  read_attributes = [
    "email",
    "email_verified",
    "name",
    "preferred_username"
  ]

  write_attributes = [
    "email",
    "name",
    "preferred_username"
  ]
}

# Create a test user
resource "aws_cognito_user" "demo_user" {
  user_pool_id = aws_cognito_user_pool.demo.id
  username     = "demo@example.com"

  attributes = {
    email          = "demo@example.com"
    email_verified = true
    name           = "Demo User"
  }

  # Initial password - user will be forced to change on first login
  temporary_password = "TempPass123!"

  lifecycle {
    ignore_changes = [
      temporary_password
    ]
  }
}
