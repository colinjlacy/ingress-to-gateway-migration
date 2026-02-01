#!/bin/bash

# Setup OAuth2 Proxy for Ingress-NGINX OIDC Authentication
# This script configures oauth2-proxy to use AWS Cognito

set -e

# Store the repo root
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "${REPO_ROOT}/eks-setup/tofu-eks"

echo "Retrieving Cognito configuration..."
COGNITO_CLIENT_ID=$(tofu output -raw cognito_ingress_nginx_client_id)
COGNITO_CLIENT_SECRET=$(tofu output -raw cognito_ingress_nginx_client_secret)
COGNITO_USER_POOL_ID=$(tofu output -raw cognito_user_pool_id)
COGNITO_ISSUER_URL=$(tofu output -raw cognito_issuer_url)

echo ""
echo "Cognito Configuration:"
echo "  Client ID: ${COGNITO_CLIENT_ID}"
echo "  User Pool ID: ${COGNITO_USER_POOL_ID}"
echo "  Issuer URL: ${COGNITO_ISSUER_URL}"
echo ""

# Generate cookie secret
COOKIE_SECRET=$(openssl rand -base64 32 | tr -d /=+ | cut -c -32)

# Create Kubernetes secret
echo "Creating oauth2-proxy secret..."
kubectl create secret generic oauth2-proxy \
  --from-literal=client-id="${COGNITO_CLIENT_ID}" \
  --from-literal=client-secret="${COGNITO_CLIENT_SECRET}" \
  --from-literal=cookie-secret="${COOKIE_SECRET}" \
  -n demo-gw-migration \
  --dry-run=client -o yaml | kubectl apply -f -

# Update the oauth2-proxy deployment with the correct issuer URL
echo "Updating oauth2-proxy deployment with Cognito issuer URL..."
cd "${REPO_ROOT}/demo"

# Use sed to replace the placeholder issuer URL
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s|REPLACE_WITH_USER_POOL_ID|${COGNITO_USER_POOL_ID}|g" 15-oauth2-proxy.yaml
else
  # Linux
  sed -i "s|REPLACE_WITH_USER_POOL_ID|${COGNITO_USER_POOL_ID}|g" 15-oauth2-proxy.yaml
fi

# Deploy oauth2-proxy
echo "Deploying oauth2-proxy..."
kubectl apply -f 15-oauth2-proxy.yaml

# Wait for oauth2-proxy to be ready
echo "Waiting for oauth2-proxy to be ready..."
kubectl wait --for=condition=ready pod -l app=oauth2-proxy -n demo-gw-migration --timeout=60s

echo ""
echo "OAuth2 Proxy setup complete!"
echo ""
echo "Test protected endpoint:"
echo "  curl -v https://nginx.colinjcodesalot.com/protected/headers"
echo ""
echo "You should be redirected to Cognito for authentication."
