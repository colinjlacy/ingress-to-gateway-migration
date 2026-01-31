#!/usr/bin/env bash
# Query MySQL database through Ingress-NGINX TCP proxy

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
log_info "MySQL TCP Connection Test - ${IMPL}"
log_info "=========================================="
echo ""

# MySQL connection details
MYSQL_HOST="${HOSTNAME}"
MYSQL_PORT="3306"
MYSQL_USER="root"
MYSQL_PASSWORD="fake_password"
MYSQL_DATABASE="socksdb"

log_info "Testing connection through ${IMPL}"
echo "Connection details:"
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
    if [ "$TARGET" == "nginx" ]; then
        echo "  1. Verify TCP service is configured: helm get values ingress-nginx -n ${NGINX_NAMESPACE}"
        echo "  2. Check DNS: dig ${MYSQL_HOST}"
        echo "  3. Check NLB security groups allow port 3306"
        echo "  4. Verify catalogue-db pod is running: kubectl get pods -n demo-gw-migration -l app=catalogue-db"
    else
        echo "  1. Verify TCPRoute is deployed: kubectl get tcproute mysql-tcp-route -n demo-gw-migration"
        echo "  2. Check Gateway listener: kubectl get gateway demo-gateway -n demo-gw-migration -o yaml"
        echo "  3. Check DNS: dig ${MYSQL_HOST}"
        echo "  4. Check NLB security groups allow port 3306"
        echo "  5. Verify catalogue-db pod is running: kubectl get pods -n demo-gw-migration -l app=catalogue-db"
    fi
    exit 1
fi

echo ""
log_info "=========================================="
log_info "MySQL test complete!"
log_info "=========================================="
echo ""
