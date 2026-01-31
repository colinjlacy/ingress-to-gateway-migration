# Demo Files - Apply Order

This directory contains numbered demo files to be applied in sequence.

## Quick Reference

### Initial Setup
```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 10-app.yaml
```

### ingress-nginx Path
```bash
# Install controller first (see ../scripts/10-install-ingress-nginx.sh)
kubectl apply -f 20-ingress-nginx-ingress.yaml
```

### Envoy Gateway Path
```bash
# Install controller first (see ../scripts/30-install-envoy-gateway.sh)
kubectl apply -f 35-envoy-proxy-config.yaml    # CRITICAL: NLB configuration
kubectl apply -f 30-envoy-gateway-gatewayclass.yaml
kubectl apply -f 40-gateway.yaml
kubectl apply -f 50-httproute-baseline.yaml
```

### Optional: Canary Routing
```bash
kubectl apply -f 60-httproute-canary.yaml
```

## Architecture: Monolithic Ingress vs Separated HTTPRoutes

This demo showcases a critical architectural difference:

### The Ingress Approach (Single File)
- **File:** `20-ingress-nginx-ingress.yaml` (300+ lines)
- **Pattern:** All teams' routes in one configuration
- **Reality:** What happens in production after 2+ years

**Problems demonstrated:**
1. ❌ Merge conflicts between teams
2. ❌ Global annotations affect everyone
3. ❌ Timeout compromises (Product needs 60s, Catalog needs 15s → set to 45s)
4. ❌ CORS enabled globally (only one team needs it)
5. ❌ Session affinity forced on stateless services
6. ❌ Rate limiting affects health checks
7. ❌ Ownership unclear ("Added by X team", "TODO: remove after...")
8. ❌ Legacy paths accumulate forever
9. ❌ Changes are risky (one edit affects all services)

### The Gateway API Approach (Multiple Files)
- **Files:** `50-httproute-*.yaml`, `51-httproute-*.yaml`, etc.
- **Pattern:** One HTTPRoute per service (or per team)
- **Reality:** How it should be architected from the start

**Benefits demonstrated:**
1. ✅ Clear ownership per file
2. ✅ Independent deployment and rollback
3. ✅ Service-specific configuration (timeouts, CORS, rate limits)
4. ✅ No merge conflicts between teams
5. ✅ Policy attachment per route
6. ✅ Easy to understand and maintain
7. ✅ Scalable to dozens of services
8. ✅ Team empowerment

**See `ROUTES-COMPARISON.md` for detailed analysis.**

---

## File Descriptions

### `00-namespace.yaml`
Creates the `demo-gw-migration` namespace for isolation.

### `10-app.yaml`
Deploys the Istio Bookinfo application:
- productpage (main entry point)
- reviews v1 (no stars) and v2 (black stars) for canary demo
- details and ratings (supporting services)

### `20-ingress-nginx-ingress.yaml`
Kubernetes Ingress resource for ingress-nginx controller.

**Key AWS Integration Points:**
- NLB annotations CAN be added here OR in Helm values (Helm values recommended)
- ACM certificate ARN placeholder
- Optional: subnet, security group, health check overrides

**Required Before Apply:**
- ingress-nginx controller installed
- ACM certificate ARN configured in controller Service annotations

### `30-envoy-gateway-gatewayclass.yaml`
Defines the GatewayClass pointing to Envoy Gateway controller.

### `35-envoy-proxy-config.yaml` ⚠️ **CRITICAL**
EnvoyProxy resource that configures the data plane Service.

**This is where AWS NLB provisioning happens for Envoy Gateway!**

**Key AWS Integration Points:**
- ✅ NLB type annotation
- ✅ ACM certificate ARN (PLACEHOLDER - must replace)
- ✅ Internet-facing scheme
- ✅ TLS ports configuration
- ✅ Optional: Subnets, security groups, EIPs
- ✅ Optional: Health checks, target group attributes
- ✅ Optional: Access logs (requires S3 bucket)

**Must replace before applying:**
```yaml
service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "PLACEHOLDER_ACM_CERT_ARN"
```

### `40-gateway.yaml`
Gateway resource that creates the actual proxy instance.

**Important:** References the EnvoyProxy configuration via `infrastructure.parametersRef`

### `50-httproute-baseline.yaml`
Product team's HTTPRoute for productpage service.

**Key points:**
- Clean, focused configuration (50 lines vs 300+ in Ingress)
- Clear ownership labels
- Separate routes for main app, health checks, and metrics

### `51-httproute-details.yaml`
Catalog team's HTTPRoute for details service.

**Key points:**
- Independent configuration from other teams
- Can set custom timeout (15s) without affecting others
- Legacy API path clearly marked for deprecation
- Dedicated health check route

### `52-httproute-reviews.yaml`
Reviews team's HTTPRoute for reviews service (v1 and beta).

**Key points:**
- Two separate HTTPRoutes (stable and beta) for flexibility
- Can set longer timeout (60s) as needed
- Partner API path with contractual obligation note
- Method-based routing (POST to /reviews/submit)

### `53-httproute-ratings.yaml`
Analytics team's HTTPRoute for ratings service.

**Key points:**
- No session affinity (stateless service)
- Query parameter routing for API versioning
- Webhook endpoint with security notes
- Independent rate limiting configuration

### `60-httproute-canary.yaml`
HTTPRoute with weighted traffic splitting:
- 90% to reviews v1
- 10% to reviews v2

Demonstrates advanced routing without controller-specific annotations.

### `ROUTES-COMPARISON.md`
Detailed analysis of the Ingress vs Gateway API approach.

**Covers:**
- Side-by-side comparison of specific features
- Why the Ingress became fragile
- How Gateway API solves each problem
- Migration strategy
- File organization recommendations
- Demo talking points

**Read this before the webinar!**

### `70-route53-dns-notes.md`
Complete guide for creating Route53 DNS records.

**Covers:**
- AWS Console steps
- AWS CLI commands
- Alias record configuration
- Troubleshooting DNS propagation

### `80-acm-tls-and-lb-notes.md`
Complete guide for ACM certificates and NLB configuration.

**Covers:**
- TLS architecture (termination at NLB vs in-cluster)
- Creating and validating ACM certificates
- All AWS annotations and their purposes
- Health check configuration
- Troubleshooting LoadBalancer issues

### `99-cleanup.yaml`
Instructions and commands for cleaning up all demo resources.

## AWS Integration Summary

### For ingress-nginx:
**Primary location:** `../install/ingress-nginx-values.yaml`
- Service annotations for NLB provisioning
- ACM certificate ARN
- All AWS integration settings

**Secondary location:** `20-ingress-nginx-ingress.yaml` (optional overrides)

### For Envoy Gateway:
**Primary location:** `35-envoy-proxy-config.yaml` ⚠️ **MOST IMPORTANT**
- EnvoyProxy resource with Service annotations
- ACM certificate ARN
- All AWS integration settings

**Reference location:** `40-gateway.yaml`
- Must reference the EnvoyProxy resource

**Controller config:** `../install/envoy-gateway-values.yaml`
- Controller-level settings only
- Does NOT configure data plane Service

## Common Mistakes to Avoid

### ❌ Applying Gateway without EnvoyProxy config
```bash
# WRONG ORDER - Gateway won't use NLB settings
kubectl apply -f 30-envoy-gateway-gatewayclass.yaml
kubectl apply -f 40-gateway.yaml
kubectl apply -f 35-envoy-proxy-config.yaml  # Too late!
```

### ✅ Correct order
```bash
# RIGHT ORDER - EnvoyProxy config exists before Gateway
kubectl apply -f 35-envoy-proxy-config.yaml  # First!
kubectl apply -f 30-envoy-gateway-gatewayclass.yaml
kubectl apply -f 40-gateway.yaml  # References EnvoyProxy
```

### ❌ Forgetting to replace ACM ARN placeholder
Both `35-envoy-proxy-config.yaml` and `../install/ingress-nginx-values.yaml` have:
```yaml
service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "PLACEHOLDER_ACM_CERT_ARN"
```

You MUST replace this with your actual ACM certificate ARN or the NLB won't have TLS configured.

### ❌ Applying HTTPRoute before Gateway is ready
Wait for Gateway to reach "Programmed" status:
```bash
kubectl wait --for=condition=Programmed gateway/demo-gateway -n demo-gw-migration --timeout=5m
```

Then apply HTTPRoutes.

## Verification Commands

### Check all resources
```bash
kubectl get all -n demo-gw-migration
kubectl get gateway,httproute -n demo-gw-migration
kubectl get gatewayclass
```

### Check Gateway status
```bash
kubectl describe gateway demo-gateway -n demo-gw-migration
```

Look for conditions:
- `Accepted: True`
- `Programmed: True`

### Check LoadBalancer Services
```bash
# ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Envoy Gateway (created by Gateway resource)
kubectl get svc -n envoy-gateway-system
```

### Verify AWS annotations were applied
```bash
# ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller -o yaml | grep -A 20 annotations

# Envoy Gateway
kubectl get svc -n envoy-gateway-system -o yaml | grep -A 20 annotations
```

## Troubleshooting

See `../docs/quick-reference.md` for comprehensive troubleshooting commands.

Quick checks:
```bash
# Pods running?
kubectl get pods -n demo-gw-migration
kubectl get pods -n ingress-nginx
kubectl get pods -n envoy-gateway-system

# LoadBalancers provisioned?
kubectl get svc -A | grep LoadBalancer

# Gateway ready?
kubectl get gateway -n demo-gw-migration

# Routes attached?
kubectl get httproute -n demo-gw-migration
```
