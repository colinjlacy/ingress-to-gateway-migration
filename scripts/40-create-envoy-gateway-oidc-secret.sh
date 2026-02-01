#!/usr/bin/env bash
# Create Kubernetes secret for Envoy Gateway OIDC client credentials

set -e

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-set-env.sh"

echo ""
log_info "=========================================="
log_info "Creating Envoy Gateway OIDC Secret"
log_info "=========================================="
echo ""

# Change to OpenTofu directory
TOFU_DIR="${SCRIPT_DIR}/../eks-setup/tofu-eks"

if [ ! -d "$TOFU_DIR" ]; then
    log_error "OpenTofu directory not found: $TOFU_DIR"
    exit 1
fi

cd "$TOFU_DIR"

# Get client secret from OpenTofu
log_info "Retrieving client secret from OpenTofu..."
CLIENT_SECRET=$(tofu output -raw cognito_envoy_gateway_client_secret 2>/dev/null)

if [ -z "$CLIENT_SECRET" ]; then
    log_error "Failed to retrieve client secret from OpenTofu"
    echo "Make sure OpenTofu has been applied and outputs are available"
    exit 1
fi

log_success "Client secret retrieved"

# Create or update the Kubernetes secret
log_info "Creating Kubernetes secret in namespace: ${DEMO_NAMESPACE}"

kubectl create secret generic envoy-gateway-oidc-client-secret \
  --from-literal=client-secret="${CLIENT_SECRET}" \
  --namespace "${DEMO_NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

log_success "Secret created/updated: envoy-gateway-oidc-client-secret"

echo ""
log_info "=========================================="
log_info "OIDC Secret Creation Complete"
log_info "=========================================="
echo ""
