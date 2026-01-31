#!/usr/bin/env bash
# Query MySQL database through Ingress-NGINX TCP proxy

set -e

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-set-env.sh"

echo ""
log_info "=========================================="
log_info "MySQL TCP Connection Test"
log_info "=========================================="
echo ""

# Get the LoadBalancer hostname for ingress-nginx
log_info "Getting ingress-nginx LoadBalancer address..."
LB_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ${NGINX_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$LB_HOSTNAME" ]; then
    log_error "Could not get LoadBalancer hostname"
    echo "Troubleshooting:"
    echo "  1. Check if ingress-nginx is installed: kubectl get svc -n ${NGINX_NAMESPACE}"
    echo "  2. Wait for LoadBalancer provisioning: kubectl get svc ingress-nginx-controller -n ${NGINX_NAMESPACE} -w"
    exit 1
fi

log_success "LoadBalancer: ${LB_HOSTNAME}"
echo ""

# MySQL connection details
MYSQL_HOST="${LB_HOSTNAME}"
MYSQL_PORT="3306"
MYSQL_USER="root"
MYSQL_PASSWORD="fake_password"
MYSQL_DATABASE="socksdb"

log_info "Connection details:"
echo "  Host: ${MYSQL_HOST}"
echo "  Port: ${MYSQL_PORT}"
echo "  User: ${MYSQL_USER}"
echo "  Database: ${MYSQL_DATABASE}"
echo ""

# Find compatible MySQL client (need 8.x for mysql_native_password support)
MYSQL_CMD=""
if [ -f "/usr/local/mysql/bin/mysql" ]; then
    # Use system MySQL (usually 8.x which supports mysql_native_password)
    MYSQL_CMD="/usr/local/mysql/bin/mysql"
elif command -v mysql &> /dev/null; then
    MYSQL_CMD="mysql"
fi

if [ -z "$MYSQL_CMD" ]; then
    log_error "MySQL client not found"
    echo ""
    echo "Install MySQL 8.0 client: brew install mysql@8.0"
    exit 1
fi

log_info "Using MySQL client: $MYSQL_CMD"

# Test connection and run query
log_info "Testing connection to MySQL from outside the cluster..."
echo ""

if $MYSQL_CMD -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "${MYSQL_DATABASE}" -e "SELECT 1 AS test_connection;" 2>&1 | grep -v "Warning"; then
    log_success "Connection successful!"
    echo ""
    
    log_info "Querying database tables..."
    echo ""
    $MYSQL_CMD -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "${MYSQL_DATABASE}" -e "SHOW TABLES;" 2>&1 | grep -v "Warning"
    
    echo ""
    log_info "Sample query - First 5 socks:"
    echo ""
    $MYSQL_CMD -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "${MYSQL_DATABASE}" -e "SELECT * FROM sock LIMIT 5;" 2>&1 | grep -v "Warning" || echo "No data in sock table"
else
    log_error "Connection failed"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify TCP service is configured: helm get values ingress-nginx -n ${NGINX_NAMESPACE}"
    echo "  2. Check NLB security groups allow port 3306"
    echo "  3. Verify catalogue-db pod is running: kubectl get pods -n demo-gw-migration -l app=catalogue-db"
    exit 1
fi

echo ""
log_info "=========================================="
log_info "MySQL test complete!"
log_info "=========================================="
echo ""
