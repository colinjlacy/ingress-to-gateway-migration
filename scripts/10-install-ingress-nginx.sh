#!/usr/bin/env bash
# Install ingress-nginx with EKS-optimized configuration

set -e

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-set-env.sh"

log_info "Installing ingress-nginx controller..."

# Check if ACM ARN is set
if ! check_acm_arn; then
    log_error "ACM_CERT_ARN must be set before installation"
    exit 1
fi

# Add Helm repository
log_info "Adding ingress-nginx Helm repository..."
helm repo add ingress-nginx ${NGINX_CHART_REPO} 2>/dev/null || true
helm repo update ingress-nginx

# Create namespace if it doesn't exist
kubectl create namespace ${NGINX_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Create temporary values file with ACM ARN substituted
TEMP_VALUES=$(mktemp)
sed "s|PLACEHOLDER_ACM_CERT_ARN|${ACM_CERT_ARN}|g" "${SCRIPT_DIR}/../install/ingress-nginx-values.yaml" > "${TEMP_VALUES}"

# Install or upgrade ingress-nginx
log_info "Installing/upgrading ingress-nginx release..."
helm upgrade --install ${NGINX_RELEASE} ${NGINX_CHART_NAME} \
    --namespace ${NGINX_NAMESPACE} \
    --values "${TEMP_VALUES}" \
    --wait \
    --timeout 5m

# Clean up temp file
rm -f "${TEMP_VALUES}"

log_success "ingress-nginx controller installed!"

# Wait for LoadBalancer to get an external address
log_info "Waiting for LoadBalancer to provision (this may take 2-3 minutes)..."
kubectl wait --namespace ${NGINX_NAMESPACE} \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s

# Get LoadBalancer hostname
log_info "Retrieving LoadBalancer details..."
NGINX_LB=$(kubectl get svc -n ${NGINX_NAMESPACE} ${NGINX_RELEASE}-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [[ -z "${NGINX_LB}" ]]; then
    log_warning "LoadBalancer hostname not yet available. Check status with:"
    echo "  kubectl get svc -n ${NGINX_NAMESPACE} ${NGINX_RELEASE}-controller"
else
    log_success "LoadBalancer provisioned: ${NGINX_LB}"
    echo ""
    log_info "Next steps:"
    echo "  1. Create Route53 A (Alias) record:"
    echo "     Name: ${NGINX_HOSTNAME}"
    echo "     Target: ${NGINX_LB}"
    echo ""
    echo "  2. Apply the Ingress resource:"
    echo "     kubectl apply -f demo/20-ingress-nginx-ingress.yaml"
fi
