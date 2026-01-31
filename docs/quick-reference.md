# Quick Reference Guide

Essential commands and information for running the Gateway migration demo.

## Pre-Demo Checklist

### AWS Resources
- [ ] ACM certificate created and validated in `us-east-2`
- [ ] Certificate ARN saved: `_______________________________`
- [ ] Route53 hosted zone accessible: `colinjcodesalot.com`
- [ ] AWS CLI configured with appropriate credentials
- [ ] kubectl connected to EKS cluster

### Local Setup
- [ ] Repository cloned
- [ ] Scripts are executable (`chmod +x scripts/*.sh`)
- [ ] ACM_CERT_ARN set in `scripts/00-set-env.sh` or exported

## Essential Commands

### Setup
```bash
# Set ACM certificate ARN (REQUIRED)
export ACM_CERT_ARN="arn:aws:acm:us-east-2:ACCOUNT:certificate/CERT-ID"

# Source environment
source scripts/00-set-env.sh

# Verify cluster connectivity
kubectl cluster-info
kubectl get nodes
```

### Installation Sequence
```bash
# 1. Create namespace and app
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/10-app.yaml

# 2. Install and configure ingress-nginx
./scripts/10-install-ingress-nginx.sh
kubectl apply -f demo/20-ingress-nginx-ingress.yaml

# 3. Install and configure Envoy Gateway
./scripts/30-install-envoy-gateway.sh
kubectl apply -f demo/30-envoy-gateway-gatewayclass.yaml
kubectl apply -f demo/40-gateway.yaml
kubectl apply -f demo/50-httproute-baseline.yaml

# 4. Optional: Apply canary route
kubectl apply -f demo/60-httproute-canary.yaml
```

### Verification
```bash
# Check overall status
./scripts/40-demo-status.sh

# Test endpoints
./scripts/50-demo-curl.sh

# Manual tests
curl -I http://app.nginx.colinjcodesalot.com/
curl -I http://app.gateway.colinjcodesalot.com/
curl -I https://app.nginx.colinjcodesalot.com/
curl -I https://app.gateway.colinjcodesalot.com/
```

### Get Load Balancer DNS Names
```bash
# ingress-nginx LoadBalancer
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Envoy Gateway LoadBalancer
kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

### Route53 DNS Creation
```bash
# Get LB hostnames (run after installation)
NGINX_LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ENVOY_LB=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# NLB Hosted Zone ID for us-east-2
NLB_ZONE_ID="Z3AADJGX6KTTL2"

# Create Route53 records (requires your hosted zone ID)
YOUR_ZONE_ID="<YOUR_ROUTE53_HOSTED_ZONE_ID>"

# Create change batch JSON
cat > /tmp/r53-changes.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "app.nginx.colinjcodesalot.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${NLB_ZONE_ID}",
          "DNSName": "${NGINX_LB}",
          "EvaluateTargetHealth": true
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "app.gateway.colinjcodesalot.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${NLB_ZONE_ID}",
          "DNSName": "${ENVOY_LB}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

# Apply changes
aws route53 change-resource-record-sets \
  --hosted-zone-id ${YOUR_ZONE_ID} \
  --change-batch file:///tmp/r53-changes.json \
  --region us-east-2
```

## Troubleshooting Commands

### Check Pod Status
```bash
# Demo application
kubectl get pods -n demo-gw-migration

# ingress-nginx
kubectl get pods -n ingress-nginx

# Envoy Gateway
kubectl get pods -n envoy-gateway-system
```

### View Logs
```bash
# ingress-nginx controller
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50

# Envoy Gateway controller
kubectl logs -n envoy-gateway-system -l app.kubernetes.io/name=envoy-gateway --tail=50

# Envoy data plane
kubectl logs -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway --tail=50

# Application logs
kubectl logs -n demo-gw-migration -l app=productpage --tail=50
```

### Check Gateway Status
```bash
# Gateway resource
kubectl get gateway -n demo-gw-migration
kubectl describe gateway demo-gateway -n demo-gw-migration

# HTTPRoute resources
kubectl get httproute -n demo-gw-migration
kubectl describe httproute bookinfo-baseline -n demo-gw-migration
kubectl describe httproute bookinfo-canary -n demo-gw-migration

# GatewayClass
kubectl get gatewayclass
kubectl describe gatewayclass eg
```

### Check Service Status
```bash
# LoadBalancer services
kubectl get svc -n ingress-nginx
kubectl get svc -n envoy-gateway-system

# Application services
kubectl get svc -n demo-gw-migration
```

### DNS Verification
```bash
# Check DNS resolution
dig app.nginx.colinjcodesalot.com
dig app.gateway.colinjcodesalot.com

# Quick DNS check
nslookup app.nginx.colinjcodesalot.com
nslookup app.gateway.colinjcodesalot.com
```

### ACM Certificate Verification
```bash
# Check certificate status
aws acm describe-certificate \
  --certificate-arn ${ACM_CERT_ARN} \
  --region us-east-2

# Check certificate domains
aws acm describe-certificate \
  --certificate-arn ${ACM_CERT_ARN} \
  --region us-east-2 \
  --query 'Certificate.{Status:Status,Domain:DomainName,SANs:SubjectAlternativeNames}'

# Test TLS connection
openssl s_client -connect app.nginx.colinjcodesalot.com:443 -servername app.nginx.colinjcodesalot.com < /dev/null
```

### AWS LoadBalancer Verification
```bash
# List NLBs
aws elbv2 describe-load-balancers \
  --region us-east-2 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `ingress`) || contains(LoadBalancerName, `envoy`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}'

# Check listeners for a specific NLB (get ARN first)
aws elbv2 describe-listeners \
  --load-balancer-arn <NLB_ARN> \
  --region us-east-2

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN> \
  --region us-east-2
```

## Fallback Commands (If DNS Fails)

### Test with Host Header Override
```bash
# Get LoadBalancer hostnames
NGINX_LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ENVOY_LB=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=demo-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# Test with Host header
curl -H "Host: app.nginx.colinjcodesalot.com" http://${NGINX_LB}/
curl -H "Host: app.gateway.colinjcodesalot.com" http://${ENVOY_LB}/
```

### Port-Forward for Local Testing
```bash
# Port-forward to ingress-nginx controller
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80

# Test locally
curl -H "Host: app.nginx.colinjcodesalot.com" http://localhost:8080/

# Port-forward to Envoy Gateway data plane
kubectl port-forward -n envoy-gateway-system svc/<envoy-service-name> 8081:80

# Test locally
curl -H "Host: app.gateway.colinjcodesalot.com" http://localhost:8081/
```

## Cleanup Commands

### Quick Cleanup
```bash
# Delete demo resources
kubectl delete ns demo-gw-migration

# Uninstall controllers
helm uninstall ingress-nginx -n ingress-nginx
helm uninstall envoy-gateway -n envoy-gateway-system

# Delete namespaces
kubectl delete ns ingress-nginx
kubectl delete ns envoy-gateway-system
```

### Complete Cleanup (Including CRDs)
```bash
# Delete Gateway API CRDs
kubectl delete crd gatewayclasses.gateway.networking.k8s.io
kubectl delete crd gateways.gateway.networking.k8s.io
kubectl delete crd httproutes.gateway.networking.k8s.io
kubectl delete crd referencegrants.gateway.networking.k8s.io
kubectl delete crd grpcroutes.gateway.networking.k8s.io
kubectl delete crd tcproutes.gateway.networking.k8s.io
kubectl delete crd tlsroutes.gateway.networking.k8s.io
kubectl delete crd udproutes.gateway.networking.k8s.io
```

### Delete Route53 Records (CLI)
```bash
# Create deletion batch
YOUR_ZONE_ID="<YOUR_ROUTE53_HOSTED_ZONE_ID>"

cat > /tmp/r53-delete.json <<EOF
{
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "app.nginx.colinjcodesalot.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z3AADJGX6KTTL2",
          "DNSName": "${NGINX_LB}",
          "EvaluateTargetHealth": true
        }
      }
    },
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "app.gateway.colinjcodesalot.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z3AADJGX6KTTL2",
          "DNSName": "${ENVOY_LB}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

# Apply deletion
aws route53 change-resource-record-sets \
  --hosted-zone-id ${YOUR_ZONE_ID} \
  --change-batch file:///tmp/r53-delete.json
```

## Demo Timing (40-minute webinar)

| Segment | Duration | Key Points |
|---------|----------|------------|
| Introduction | 3 min | Context, objectives, environment overview |
| Part 1: ingress-nginx baseline | 8 min | Show current state, test it works |
| Part 2: Install Envoy Gateway | 5 min | Gateway API concepts, installation |
| Part 3: Routing parity | 12 min | Gateway + HTTPRoute, side-by-side test |
| Part 4: Canary deployment | 8 min | Traffic splitting, weighted backends |
| Part 5: TLS discussion | 3 min | ACM integration, architecture |
| Part 6: Migration strategy | 3 min | Best practices, pitfalls |
| Q&A buffer | ~2 min | Flexibility for delays |

## Key Talking Points

### Why Gateway API?
- ✅ Portable across implementations
- ✅ More expressive than Ingress
- ✅ Role-oriented design
- ✅ Native advanced routing features

### Why Side-by-Side?
- ✅ Zero downtime migration
- ✅ Easy rollback
- ✅ Validate parity before cutover
- ✅ Gradual confidence building

### TLS Architecture
- ✅ ACM certificates at AWS NLB
- ✅ L7 routing inside cluster
- ✅ Common EKS production pattern
- ✅ Alternative: cert-manager + in-cluster TLS

## Common Issues and Solutions

| Issue | Likely Cause | Solution |
|-------|--------------|----------|
| LoadBalancer stuck pending | IAM permissions, subnet tags | Check CloudFormation events |
| DNS not resolving | Propagation delay, wrong target | Use `dig`, fall back to Host header |
| 503 errors | Pods not ready, health checks failing | Check pod status, logs |
| TLS errors | Wrong ACM ARN, region mismatch | Verify certificate in us-east-2 |
| Gateway not Programmed | Envoy proxy not ready | Check controller logs, wait longer |
| HTTPRoute not attached | Namespace mismatch, selector issue | Check parentRef, describe Gateway |

## URLs and References

- **Gateway API Docs:** https://gateway-api.sigs.k8s.io/
- **Envoy Gateway:** https://gateway.envoyproxy.io/
- **ingress-nginx:** https://kubernetes.github.io/ingress-nginx/
- **Bookinfo App:** https://github.com/istio/istio/tree/master/samples/bookinfo
- **ACM Docs:** https://docs.aws.amazon.com/acm/
- **Route53 Docs:** https://docs.aws.amazon.com/route53/
