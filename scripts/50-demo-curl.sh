#!/usr/bin/env bash
# Test canary traffic splitting for ingress-nginx or Envoy Gateway

set -e

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-set-env.sh"

# Parse arguments
TARGET="${1:-nginx}"
DOMAIN="${2:-colinjcodesalot.com}"

if [ "$TARGET" != "nginx" ] && [ "$TARGET" != "gateway" ]; then
    log_error "Invalid target: $TARGET"
    echo "Usage: $0 [nginx|gateway] [domain]"
    echo "  default target: nginx"
    echo "  default domain: colinjcodesalot.com"
    exit 1
fi

# Set hostname based on target
if [ "$TARGET" == "nginx" ]; then
    HOSTNAME="nginx.${DOMAIN}"
    IMPL="Ingress-NGINX"
else
    HOSTNAME="gateway.${DOMAIN}"
    IMPL="Envoy Gateway"
fi

echo ""
log_info "=========================================="
log_info "Canary Traffic Split Test - ${IMPL}"
log_info "=========================================="
echo ""
log_info "Making 100 parallel requests to ${HOSTNAME}/version"
echo ""

# Test endpoint accessibility
if ! curl -s -f http://${HOSTNAME}/version >/dev/null 2>&1; then
    log_error "Cannot reach /version endpoint at ${HOSTNAME}"
    echo "Troubleshooting:"
    if [ "$TARGET" == "nginx" ]; then
        echo "  1. Check DNS: dig ${HOSTNAME}"
        echo "  2. Check service: kubectl get svc -n ${NGINX_NAMESPACE}"
        echo "  3. Check ingress: kubectl get ingress -n ${DEMO_NAMESPACE}"
    else
        echo "  1. Check DNS: dig ${HOSTNAME}"
        echo "  2. Check gateway: kubectl get gateway -n ${DEMO_NAMESPACE}"
        echo "  3. Check service: kubectl get svc -n ${ENVOY_NAMESPACE}"
        echo "  4. Check httproute: kubectl get httproute -n ${DEMO_NAMESPACE}"
    fi
    exit 1
fi

# Create temporary directory for response files
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Make 100 parallel requests
echo "Sending 100 parallel requests..."
for i in {1..100}; do
    curl -s http://${HOSTNAME}/version > "${TEMP_DIR}/response_${i}.txt" 2>/dev/null &
done

# Wait for all background jobs to complete
wait

echo "All requests complete. Analyzing results..."
echo ""

# Count versions
V1_COUNT=0
V2_COUNT=0
UNKNOWN_COUNT=0

for i in {1..100}; do
    RESPONSE=$(cat "${TEMP_DIR}/response_${i}.txt" 2>/dev/null || echo "")
    
    if echo "$RESPONSE" | grep -q '"version":"v1"' 2>/dev/null; then
        V1_COUNT=$((V1_COUNT + 1))
    elif echo "$RESPONSE" | grep -q '"version":"v2"' 2>/dev/null; then
        V2_COUNT=$((V2_COUNT + 1))
    else
        UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1))
    fi
done

# Display results
echo "Traffic Split Results:"
echo "=========================================="
echo "  v1 responses: ${V1_COUNT}/100 (${V1_COUNT}%)"
echo "  v2 responses: ${V2_COUNT}/100 (${V2_COUNT}%)"
if [ ${UNKNOWN_COUNT} -gt 0 ]; then
    echo "  unknown/error: ${UNKNOWN_COUNT}/100"
fi
echo "=========================================="
echo ""

echo ""
log_info "=========================================="
log_info "Canary test complete!"
log_info "=========================================="
echo ""
