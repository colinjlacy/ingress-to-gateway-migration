# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = module.aws_load_balancer_controller_irsa.iam_role_arn
}

# Cognito outputs for OIDC configuration
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.demo.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.demo.arn
}

output "cognito_user_pool_endpoint" {
  description = "Cognito User Pool Endpoint"
  value       = aws_cognito_user_pool.demo.endpoint
}

output "cognito_domain" {
  description = "Cognito User Pool Domain"
  value       = aws_cognito_user_pool_domain.demo.domain
}

output "cognito_issuer_url" {
  description = "OIDC Issuer URL for JWT validation"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.demo.id}"
}

output "cognito_jwks_uri" {
  description = "JWKS URI for JWT token validation"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.demo.id}/.well-known/jwks.json"
}

output "cognito_auth_url" {
  description = "Cognito Authorization URL"
  value       = "https://${aws_cognito_user_pool_domain.demo.domain}.auth.${var.region}.amazoncognito.com/oauth2/authorize"
}

output "cognito_token_url" {
  description = "Cognito Token URL"
  value       = "https://${aws_cognito_user_pool_domain.demo.domain}.auth.${var.region}.amazoncognito.com/oauth2/token"
}

output "cognito_userinfo_url" {
  description = "Cognito UserInfo URL"
  value       = "https://${aws_cognito_user_pool_domain.demo.domain}.auth.${var.region}.amazoncognito.com/oauth2/userInfo"
}

# Ingress-NGINX client credentials
output "cognito_ingress_nginx_client_id" {
  description = "Cognito App Client ID for Ingress-NGINX"
  value       = aws_cognito_user_pool_client.ingress_nginx.id
}

output "cognito_ingress_nginx_client_secret" {
  description = "Cognito App Client Secret for Ingress-NGINX"
  value       = aws_cognito_user_pool_client.ingress_nginx.client_secret
  sensitive   = true
}

# Envoy Gateway client credentials
output "cognito_envoy_gateway_client_id" {
  description = "Cognito App Client ID for Envoy Gateway"
  value       = aws_cognito_user_pool_client.envoy_gateway.id
}

output "cognito_envoy_gateway_client_secret" {
  description = "Cognito App Client Secret for Envoy Gateway"
  value       = aws_cognito_user_pool_client.envoy_gateway.client_secret
  sensitive   = true
}

# Demo user credentials
output "cognito_demo_user_username" {
  description = "Demo user username (email)"
  value       = aws_cognito_user.demo_user.username
}

output "cognito_demo_user_temp_password" {
  description = "Demo user temporary password (change on first login)"
  value       = "TempPass123!"
  sensitive   = true
}
