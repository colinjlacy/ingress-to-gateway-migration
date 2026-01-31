#!/usr/bin/env bash
# Environment configuration for the Gateway migration demo
# Source this file before running other scripts: source scripts/00-set-env.sh

set -e

# AWS Configuration
export AWS_REGION="us-east-2"
export DOMAIN="colinjcodesalot.com"

# Demo Configuration
export DEMO_NAMESPACE="demo-gw-migration"
export NGINX_HOSTNAME="app.nginx.${DOMAIN}"
export GATEWAY_HOSTNAME="app.gateway.${DOMAIN}"

# ACM Certificate ARN - REPLACE THIS WITH YOUR ACTUAL ARN
export ACM_CERT_ARN="PLACEHOLDER_ACM_CERT_ARN"

# Ingress-NGINX Configuration
export NGINX_NAMESPACE="ingress-nginx"
export NGINX_RELEASE="ingress-nginx"
export NGINX_CHART_REPO="https://kubernetes.github.io/ingress-nginx"
export NGINX_CHART_NAME="ingress-nginx/ingress-nginx"

# Envoy Gateway Configuration
export ENVOY_NAMESPACE="envoy-gateway-system"
export ENVOY_RELEASE="envoy-gateway"
export ENVOY_CHART="oci://docker.io/envoyproxy/gateway-helm"

# Color output helpers
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate ACM ARN is set
check_acm_arn() {
    if [[ "${ACM_CERT_ARN}" == "PLACEHOLDER_ACM_CERT_ARN" ]]; then
        log_warning "ACM_CERT_ARN is not set!"
        log_warning "Update this variable with your actual ACM certificate ARN"
        log_warning "Or export it: export ACM_CERT_ARN='arn:aws:acm:us-east-2:...'"
        return 1
    fi
    return 0
}

log_info "Environment variables loaded:"
echo "  AWS_REGION:       ${AWS_REGION}"
echo "  DOMAIN:           ${DOMAIN}"
echo "  DEMO_NAMESPACE:   ${DEMO_NAMESPACE}"
echo "  NGINX_HOSTNAME:   ${NGINX_HOSTNAME}"
echo "  GATEWAY_HOSTNAME: ${GATEWAY_HOSTNAME}"
echo ""

if ! check_acm_arn; then
    log_warning "Remember to set ACM_CERT_ARN before running installation scripts!"
fi
