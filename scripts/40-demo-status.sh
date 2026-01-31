#!/usr/bin/env bash
# Display status of all demo components

set -e

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-set-env.sh"

echo ""
log_info "=========================================="
log_info "Gateway Migration Demo Status"
log_info "=========================================="
echo ""

# Demo namespace and applications
log_info "Demo Namespace and Applications:"
echo "----------------------------------------"
if kubectl get namespace ${DEMO_NAMESPACE} &>/dev/null; then
    log_success "Namespace: ${DEMO_NAMESPACE} exists"
    
    # Check pods
    echo ""
    echo "Pods:"
    kubectl get pods -n ${DEMO_NAMESPACE} -o wide
    
    # Check services
    echo ""
    echo "Services:"
    kubectl get svc -n ${DEMO_NAMESPACE}
else
    log_warning "Namespace ${DEMO_NAMESPACE} does not exist"
    echo "Create it with: kubectl apply -f demo/00-namespace.yaml"
fi

echo ""
log_info "=========================================="
log_info "Ingress-NGINX Status"
log_info "=========================================="
echo ""

if kubectl get namespace ${NGINX_NAMESPACE} &>/dev/null; then
    log_success "Namespace: ${NGINX_NAMESPACE} exists"
    
    # Controller pods
    echo ""
    echo "Controller Pods:"
    kubectl get pods -n ${NGINX_NAMESPACE} -l app.kubernetes.io/component=controller
    
    # LoadBalancer Service
    echo ""
    echo "LoadBalancer Service:"
    kubectl get svc -n ${NGINX_NAMESPACE} ${NGINX_RELEASE}-controller
    
    NGINX_LB=$(kubectl get svc -n ${NGINX_NAMESPACE} ${NGINX_RELEASE}-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [[ -n "${NGINX_LB}" ]]; then
        log_success "LoadBalancer: ${NGINX_LB}"
    else
        log_warning "LoadBalancer not yet provisioned"
    fi
    
    # Ingress resources
    if kubectl get namespace ${DEMO_NAMESPACE} &>/dev/null; then
        echo ""
        echo "Ingress Resources:"
        kubectl get ingress -n ${DEMO_NAMESPACE} 2>/dev/null || echo "  No ingress resources found"
    fi
else
    log_warning "Namespace ${NGINX_NAMESPACE} does not exist"
    echo "Install with: ./scripts/10-install-ingress-nginx.sh"
fi

echo ""
log_info "=========================================="
log_info "Envoy Gateway Status"
log_info "=========================================="
echo ""

if kubectl get namespace ${ENVOY_NAMESPACE} &>/dev/null; then
    log_success "Namespace: ${ENVOY_NAMESPACE} exists"
    
    # Controller deployment
    echo ""
    echo "Controller Deployment:"
    kubectl get deployment -n ${ENVOY_NAMESPACE} envoy-gateway
    
    # Gateway resources
    if kubectl get namespace ${DEMO_NAMESPACE} &>/dev/null; then
        echo ""
        echo "GatewayClass:"
        kubectl get gatewayclass 2>/dev/null || echo "  No GatewayClass found"
        
        echo ""
        echo "Gateway:"
        kubectl get gateway -n ${DEMO_NAMESPACE} 2>/dev/null || echo "  No Gateway found"
        
        # If Gateway exists, show detailed status
        if kubectl get gateway -n ${DEMO_NAMESPACE} demo-gateway &>/dev/null; then
            echo ""
            echo "Gateway Detailed Status:"
            kubectl describe gateway -n ${DEMO_NAMESPACE} demo-gateway | grep -A 10 "Status:"
        fi
        
        echo ""
        echo "HTTPRoutes:"
        kubectl get httproute -n ${DEMO_NAMESPACE} 2>/dev/null || echo "  No HTTPRoutes found"
        
        # Data plane services
        echo ""
        echo "Data Plane Services:"
        kubectl get svc -n ${ENVOY_NAMESPACE} 2>/dev/null | grep -v "NAME" || echo "  No services found yet"
        
        ENVOY_LB=$(kubectl get svc -n ${ENVOY_NAMESPACE} -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [[ -n "${ENVOY_LB}" ]]; then
            log_success "LoadBalancer: ${ENVOY_LB}"
        fi
    fi
else
    log_warning "Namespace ${ENVOY_NAMESPACE} does not exist"
    echo "Install with: ./scripts/30-install-envoy-gateway.sh"
fi

echo ""
log_info "=========================================="
log_info "DNS Configuration Needed"
log_info "=========================================="
echo ""

if [[ -n "${NGINX_LB}" ]]; then
    echo "Create Route53 A (Alias) record:"
    echo "  Name: ${NGINX_HOSTNAME}"
    echo "  Type: A (Alias)"
    echo "  Target: ${NGINX_LB}"
    echo ""
fi

if [[ -n "${ENVOY_LB}" ]]; then
    echo "Create Route53 A (Alias) record:"
    echo "  Name: ${GATEWAY_HOSTNAME}"
    echo "  Type: A (Alias)"
    echo "  Target: ${ENVOY_LB}"
    echo ""
fi

echo ""
log_info "Demo status check complete!"
echo ""
