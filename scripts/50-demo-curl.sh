#!/usr/bin/env bash
# Run demo curl commands to test both ingress-nginx and Envoy Gateway

set -e

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-set-env.sh"

echo ""
log_info "=========================================="
log_info "Gateway Migration Demo - Traffic Tests"
log_info "=========================================="
echo ""

# Test ingress-nginx
log_info "Testing ingress-nginx (${NGINX_HOSTNAME})..."
echo "----------------------------------------"

echo ""
log_info "HTTP Test:"
if curl -s -f -H "Host: ${NGINX_HOSTNAME}" http://${NGINX_HOSTNAME}/ >/dev/null 2>&1; then
    log_success "HTTP connection successful"
    echo ""
    echo "Response preview:"
    curl -s -H "Host: ${NGINX_HOSTNAME}" http://${NGINX_HOSTNAME}/ | head -20
else
    log_error "HTTP connection failed"
    echo "Troubleshooting:"
    echo "  1. Check DNS: dig ${NGINX_HOSTNAME}"
    echo "  2. Check service: kubectl get svc -n ${NGINX_NAMESPACE}"
    echo "  3. Check ingress: kubectl get ingress -n ${DEMO_NAMESPACE}"
fi

echo ""
log_info "HTTPS Test:"
if curl -s -f https://${NGINX_HOSTNAME}/ >/dev/null 2>&1; then
    log_success "HTTPS connection successful"
    echo ""
    echo "Response headers:"
    curl -s -I https://${NGINX_HOSTNAME}/ | grep -i "x-demo-edge\|server\|content-type" || true
else
    log_warning "HTTPS connection failed (may need DNS propagation or ACM setup)"
fi

echo ""
echo ""

# Test Envoy Gateway
log_info "Testing Envoy Gateway (${GATEWAY_HOSTNAME})..."
echo "----------------------------------------"

echo ""
log_info "HTTP Test:"
if curl -s -f -H "Host: ${GATEWAY_HOSTNAME}" http://${GATEWAY_HOSTNAME}/ >/dev/null 2>&1; then
    log_success "HTTP connection successful"
    echo ""
    echo "Response preview:"
    curl -s -H "Host: ${GATEWAY_HOSTNAME}" http://${GATEWAY_HOSTNAME}/ | head -20
else
    log_error "HTTP connection failed"
    echo "Troubleshooting:"
    echo "  1. Check DNS: dig ${GATEWAY_HOSTNAME}"
    echo "  2. Check gateway: kubectl get gateway -n ${DEMO_NAMESPACE}"
    echo "  3. Check service: kubectl get svc -n ${ENVOY_NAMESPACE}"
    echo "  4. Check httproute: kubectl get httproute -n ${DEMO_NAMESPACE}"
fi

echo ""
log_info "HTTPS Test:"
if curl -s -f https://${GATEWAY_HOSTNAME}/ >/dev/null 2>&1; then
    log_success "HTTPS connection successful"
    echo ""
    echo "Response headers:"
    curl -s -I https://${GATEWAY_HOSTNAME}/ | grep -i "x-demo-edge\|server\|content-type" || true
else
    log_warning "HTTPS connection failed (may need DNS propagation or ACM setup)"
fi

echo ""
echo ""

# Test header differences
log_info "Comparing edge headers..."
echo "----------------------------------------"

echo ""
echo "ingress-nginx X-Demo-Edge header:"
curl -s -I http://${NGINX_HOSTNAME}/ 2>/dev/null | grep -i "x-demo-edge" || echo "  (not found)"

echo ""
echo "Envoy Gateway X-Demo-Edge header:"
curl -s -I http://${GATEWAY_HOSTNAME}/ 2>/dev/null | grep -i "x-demo-edge" || echo "  (not found)"

echo ""
echo ""

# Canary/traffic splitting test
log_info "Testing canary traffic split (Envoy Gateway)..."
echo "----------------------------------------"
echo ""
log_info "This test checks if reviews v1 (no stars) vs v2 (black stars) are weighted correctly"
log_info "Note: The Bookinfo app's internal routing means you may not see the split from the main page"
log_info "Sending 50 requests and counting versions..."
echo ""

# Note: This is a simplified test. In a real scenario with the Bookinfo app,
# you'd need to either:
# 1. Call the reviews service directly through the gateway
# 2. Use a service mesh for internal traffic splitting
# 3. Modify the canary route to test different services

if curl -s -f http://${GATEWAY_HOSTNAME}/ >/dev/null 2>&1; then
    V1_COUNT=0
    V2_COUNT=0
    
    for i in {1..50}; do
        RESPONSE=$(curl -s http://${GATEWAY_HOSTNAME}/ 2>/dev/null || echo "")
        
        # Check if response contains indicators of different versions
        # This is simplified - actual detection would depend on the app's output
        if echo "$RESPONSE" | grep -q "reviews-v1\|no stars" 2>/dev/null; then
            V1_COUNT=$((V1_COUNT + 1))
        elif echo "$RESPONSE" | grep -q "reviews-v2\|black stars" 2>/dev/null; then
            V2_COUNT=$((V2_COUNT + 1))
        fi
        
        # Progress indicator
        if [ $((i % 10)) -eq 0 ]; then
            echo -n "."
        fi
    done
    
    echo ""
    echo ""
    echo "Results (if detectable):"
    echo "  Version 1 responses: ${V1_COUNT}"
    echo "  Version 2 responses: ${V2_COUNT}"
    echo ""
    log_info "Note: The Bookinfo productpage may not clearly show version differences"
    log_info "To see the canary effect, consider calling /reviews directly if exposed"
else
    log_warning "Cannot test canary - gateway not accessible"
fi

echo ""
log_info "=========================================="
log_info "Demo traffic tests complete!"
log_info "=========================================="
echo ""
