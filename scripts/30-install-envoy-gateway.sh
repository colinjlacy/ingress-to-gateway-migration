#!/usr/bin/env bash
# Install Envoy Gateway with EKS-optimized configuration

set -e

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-set-env.sh"

log_info "Installing Envoy Gateway..."

# Check if ACM ARN is set
if ! check_acm_arn; then
    log_error "ACM_CERT_ARN must be set before installation"
    exit 1
fi

# Install Gateway API CRDs if not already present
log_info "Checking Gateway API CRDs..."
if ! kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
    log_info "Installing Gateway API CRDs..."
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
    log_success "Gateway API CRDs installed"
else
    log_info "Gateway API CRDs already present"
fi

# Create namespace if it doesn't exist
kubectl create namespace ${ENVOY_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Create temporary values file with ACM ARN substituted
TEMP_VALUES=$(mktemp)
sed "s|PLACEHOLDER_ACM_CERT_ARN|${ACM_CERT_ARN}|g" "${SCRIPT_DIR}/../install/envoy-gateway-values.yaml" > "${TEMP_VALUES}"

# Install or upgrade Envoy Gateway
log_info "Installing/upgrading Envoy Gateway release..."
helm upgrade --install ${ENVOY_RELEASE} ${ENVOY_CHART} \
    --namespace ${ENVOY_NAMESPACE} \
    --values "${TEMP_VALUES}" \
    --wait \
    --timeout 5m

# Clean up temp file
rm -f "${TEMP_VALUES}"

log_success "Envoy Gateway installed!"

# Wait for controller to be ready
log_info "Waiting for Envoy Gateway controller to be ready..."
kubectl wait --namespace ${ENVOY_NAMESPACE} \
    --for=condition=available deployment/envoy-gateway \
    --timeout=300s

log_success "Envoy Gateway controller is ready!"

# Note about data plane
log_info ""
log_info "Note: The Envoy data plane Service will be created when you apply a Gateway resource."
log_info ""
log_info "Next steps:"
echo "  1. Apply EnvoyProxy configuration (defines NLB settings):"
echo "     kubectl apply -f demo/35-envoy-proxy-config.yaml"
echo ""
echo "  2. Apply Gateway resources:"
echo "     kubectl apply -f demo/30-envoy-gateway-gatewayclass.yaml"
echo "     kubectl apply -f demo/40-gateway.yaml"
echo ""
echo "  3. Wait for Gateway to be ready, then get LoadBalancer:"
echo "     kubectl get gateway -n ${DEMO_NAMESPACE} demo-gateway"
echo "     kubectl get svc -n ${ENVOY_NAMESPACE}"
echo ""
echo "  4. Create Route53 A (Alias) record for the LoadBalancer"
