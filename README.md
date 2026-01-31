# Ingress-NGINX to Envoy Gateway Migration Demo

A complete, production-ready demo showing how to migrate from **ingress-nginx** to **Envoy Gateway** (Gateway API) on **Amazon EKS**, featuring:

- 🔄 Side-by-side migration with zero downtime
- 🌐 Route53 DNS integration
- 🔒 AWS Certificate Manager (ACM) for TLS
- ⚖️ Traffic splitting and canary deployments
- 📦 Real application (Istio Bookinfo)
- 🎯 Complete webinar-ready materials

## Quick Start

### Prerequisites

- EKS cluster in `us-east-2` region
- `kubectl` configured and connected
- `helm` installed (v3+)
- AWS CLI configured
- Route53 hosted zone: `colinjcodesalot.com`
- ACM certificate (create before starting - see [ACM Setup](#acm-setup))

### 5-Minute Demo Setup

```bash
# 1. Set your ACM certificate ARN
export ACM_CERT_ARN="arn:aws:acm:us-east-2:ACCOUNT:certificate/CERT-ID"

# 2. Source environment variables
source scripts/00-set-env.sh

# 3. Create demo namespace and deploy application
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/10-app.yaml

# 4. Install ingress-nginx
./scripts/10-install-ingress-nginx.sh
kubectl apply -f demo/20-ingress-nginx-ingress.yaml

# 5. Install Envoy Gateway and configure NLB
./scripts/30-install-envoy-gateway.sh
kubectl apply -f demo/35-envoy-proxy-config.yaml
kubectl apply -f demo/30-envoy-gateway-gatewayclass.yaml
kubectl apply -f demo/40-gateway.yaml
kubectl apply -f demo/50-httproute-baseline.yaml  # Product team routes
kubectl apply -f demo/51-httproute-details.yaml   # Catalog team routes
kubectl apply -f demo/52-httproute-reviews.yaml   # Reviews team routes
kubectl apply -f demo/53-httproute-ratings.yaml   # Analytics team routes

# 6. Configure Route53 DNS (see demo/70-route53-dns-notes.md)

# 7. Check status
./scripts/40-demo-status.sh

# 8. Test both endpoints
./scripts/50-demo-curl.sh
```

## Repository Structure

```
.
├── demo/                          # Numbered demo manifests
│   ├── 00-namespace.yaml         # Demo namespace
│   ├── 10-app.yaml               # Bookinfo application
│   ├── 20-ingress-nginx-ingress.yaml   # Ingress resource
│   ├── 30-envoy-gateway-gatewayclass.yaml  # GatewayClass
│   ├── 35-envoy-proxy-config.yaml    # EnvoyProxy config (NLB settings)
│   ├── 40-gateway.yaml           # Gateway resource
│   ├── 50-httproute-baseline.yaml    # Baseline routing
│   ├── 60-httproute-canary.yaml      # Canary/traffic split
│   ├── 70-route53-dns-notes.md   # DNS configuration guide
│   ├── 80-acm-tls-and-lb-notes.md    # TLS and LB setup
│   └── 99-cleanup.yaml           # Cleanup resources
│
├── install/                       # Helm values
│   ├── ingress-nginx-values.yaml # ingress-nginx config
│   └── envoy-gateway-values.yaml # Envoy Gateway config
│
├── scripts/                       # Automation scripts
│   ├── 00-set-env.sh             # Environment variables
│   ├── 10-install-ingress-nginx.sh   # Install ingress-nginx
│   ├── 30-install-envoy-gateway.sh   # Install Envoy Gateway
│   ├── 40-demo-status.sh         # Show demo status
│   └── 50-demo-curl.sh           # Test endpoints
│
└── docs/                          # Documentation
    └── talk-track.md             # 40-min webinar script
```

## ACM Setup

### Create Certificate

```bash
# Option 1: Wildcard certificate (recommended)
aws acm request-certificate \
  --domain-name "*.colinjcodesalot.com" \
  --validation-method DNS \
  --region us-east-2

# Option 2: Specific hostnames
aws acm request-certificate \
  --domain-name "app.nginx.colinjcodesalot.com" \
  --subject-alternative-names "app.gateway.colinjcodesalot.com" \
  --validation-method DNS \
  --region us-east-2
```

### Validate Certificate

1. Get the certificate ARN from the output
2. Retrieve validation records:
   ```bash
   aws acm describe-certificate \
     --certificate-arn <YOUR_ARN> \
     --region us-east-2
   ```
3. Add the CNAME validation records to Route53
4. Wait for status to become "Issued" (5-10 minutes)

## Architecture

### TLS and Load Balancer Flow

```
┌─────────┐
│ Internet│
└────┬────┘
     │ HTTPS (443)
     ▼
┌─────────────────────────┐
│ AWS Network Load        │
│ Balancer (NLB)          │
│ - TLS termination (ACM) │
│ - Ports 80 & 443        │
└────┬────────────────────┘
     │ HTTP (80)
     ▼
┌─────────────────────────┐
│ Ingress Controller      │
│ (nginx or Envoy)        │
│ - L7 routing            │
│ - Host/path matching    │
└────┬────────────────────┘
     │ HTTP
     ▼
┌─────────────────────────┐
│ Application Services    │
│ (Bookinfo)              │
└─────────────────────────┘
```

### Key Points

- **TLS termination** happens at the AWS NLB using ACM certificates
- **L7 routing** happens at the ingress controller (host/path-based)
- **Two parallel stacks** enable safe side-by-side migration

## What This Demo Shows

### Before: ingress-nginx
- Standard Kubernetes `Ingress` resource
- Controller-specific annotations
- Works well but limited extensibility

### After: Envoy Gateway + Gateway API
- `Gateway` + `HTTPRoute` resources
- Portable, standardized configuration
- Advanced routing capabilities built-in

### Migration Benefits
✅ **Standardization** - Portable across implementations  
✅ **Expressiveness** - Native traffic splitting, header matching, etc.  
✅ **Role-oriented** - Separation between platform and app concerns  
✅ **Extensibility** - Policy attachments for advanced features  

## Demo Scenarios

### 1. Routing Parity
Show identical routing behavior with both stacks:
- Same backend application
- Same hostname-based routing
- Different custom headers to prove the path

### 2. Traffic Splitting (Canary)
Demonstrate weighted routing with Gateway API:
- 90% traffic to reviews-v1
- 10% traffic to reviews-v2 (canary)
- Declarative, no annotations needed

### 3. Side-by-Side Operation
Prove both stacks can coexist:
- Two hostnames, two load balancers
- Independent operation
- Gradual migration path

## Customization

### Using Your Own Domain

1. Update `scripts/00-set-env.sh`:
   ```bash
   export DOMAIN="yourdomain.com"
   ```

2. Update manifests:
   ```bash
   # Update ingress hostname
   sed -i '' 's/colinjcodesalot.com/yourdomain.com/g' demo/20-ingress-nginx-ingress.yaml
   
   # Update HTTPRoute hostnames
   sed -i '' 's/colinjcodesalot.com/yourdomain.com/g' demo/50-httproute-baseline.yaml
   sed -i '' 's/colinjcodesalot.com/yourdomain.com/g' demo/60-httproute-canary.yaml
   ```

### Using a Different Application

The demo uses Istio Bookinfo, but you can substitute any HTTP application:

1. Replace `demo/10-app.yaml` with your app manifests
2. Update service names in ingress/route manifests
3. Adjust the canary scenario if using different services

## Troubleshooting

### LoadBalancer Not Provisioning

Check Service events:
```bash
kubectl describe svc -n ingress-nginx ingress-nginx-controller
kubectl describe svc -n envoy-gateway-system
```

Verify annotations:
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller -o yaml | grep annotations -A 10
```

### Gateway Not Ready

Check Gateway status:
```bash
kubectl describe gateway demo-gateway -n demo-gw-migration
```

Check controller logs:
```bash
kubectl logs -n envoy-gateway-system -l app.kubernetes.io/name=envoy-gateway
```

### DNS Not Resolving

Test propagation:
```bash
dig app.nginx.colinjcodesalot.com
dig app.gateway.colinjcodesalot.com
```

Fallback test with direct LB access:
```bash
NLB_DNS=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -H "Host: app.nginx.colinjcodesalot.com" http://${NLB_DNS}/
```

### TLS Certificate Issues

Verify certificate status:
```bash
aws acm describe-certificate \
  --certificate-arn ${ACM_CERT_ARN} \
  --region us-east-2 \
  --query 'Certificate.Status'
```

Check certificate domains:
```bash
aws acm describe-certificate \
  --certificate-arn ${ACM_CERT_ARN} \
  --region us-east-2 \
  --query 'Certificate.{Domain:DomainName,SANs:SubjectAlternativeNames}'
```

## Cleanup

### Quick Cleanup
```bash
# Delete demo namespace (removes app and Gateway/Ingress resources)
kubectl delete ns demo-gw-migration

# Uninstall controllers
helm uninstall ingress-nginx -n ingress-nginx
helm uninstall envoy-gateway -n envoy-gateway-system

# Delete controller namespaces
kubectl delete ns ingress-nginx
kubectl delete ns envoy-gateway-system
```

### Complete Cleanup
```bash
# Also remove CRDs (optional - only if you want a completely clean slate)
kubectl delete crd gatewayclasses.gateway.networking.k8s.io
kubectl delete crd gateways.gateway.networking.k8s.io
kubectl delete crd httproutes.gateway.networking.k8s.io

# Delete Route53 records (manual or via CLI)
# Note: ACM certificate and Route53 hosted zone remain (manual cleanup if desired)
```

## Webinar Preparation

For presenters running this as a webinar:

### Before the Webinar
- [ ] Create and validate ACM certificate
- [ ] Run through the demo end-to-end at least twice
- [ ] Pre-create Route53 records or have the CLI commands ready
- [ ] Test from the network you'll present from (firewall/VPN considerations)
- [ ] Verify both HTTP and HTTPS work
- [ ] Bookmark the AWS Console pages you'll show

### During the Webinar
- [ ] Follow `docs/talk-track.md` for timing and talking points
- [ ] Use `scripts/40-demo-status.sh` to quickly verify state
- [ ] Have backup curl commands ready if DNS is slow
- [ ] Show the AWS Console for NLB/ACM if time permits

### After the Webinar
- [ ] Share the repository link
- [ ] Clean up AWS resources to avoid charges
- [ ] Document any issues for the next rehearsal

## Additional Resources

- **Gateway API Official Docs:** https://gateway-api.sigs.k8s.io/
- **Envoy Gateway Docs:** https://gateway.envoyproxy.io/
- **ingress-nginx Docs:** https://kubernetes.github.io/ingress-nginx/
- **AWS Load Balancer Controller:** https://kubernetes-sigs.github.io/aws-load-balancer-controller/

## Contributing

This is a demo repository. If you find issues or have improvements:

1. Test your changes end-to-end
2. Update relevant documentation
3. Ensure scripts remain idempotent
4. Submit a PR with a clear description

## License

See [LICENSE](LICENSE) file for details.

---

**Questions or Issues?**

This demo is designed to be self-contained and rehearsal-ready. If something isn't working:
1. Check the troubleshooting section above
2. Review the detailed notes in `demo/70-route53-dns-notes.md` and `demo/80-acm-tls-and-lb-notes.md`
3. Use `./scripts/40-demo-status.sh` to diagnose the state
4. Check pod logs for the controllers and application
A repo demonstrating how to migrate from Nginx Ingress to the Gateway API using Envoy Gateway
