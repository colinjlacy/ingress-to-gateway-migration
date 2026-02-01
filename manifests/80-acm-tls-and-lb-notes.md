# ACM TLS and Load Balancer Configuration Notes

## Overview
This demo uses **AWS Certificate Manager (ACM)** for TLS certificates and **Network Load Balancers (NLB)** for internet-facing entry points. TLS termination happens **at the AWS load balancer**, not inside the Kubernetes cluster.

## Architecture

```
Internet → Route53 DNS → NLB (TLS termination with ACM) → HTTP → Ingress Controller Pod → HTTP → Application Pod
```

### Key Points
- **ACM certificates** live in AWS and cannot be exported to Kubernetes Secrets
- **NLB terminates TLS** on port 443 using the ACM certificate
- **NLB forwards HTTP** on port 80 to the controller pod
- **Controllers perform L7 routing** based on Host header and path

## ACM Certificate

### Certificate Details
- **Region**: us-east-2 (must match EKS cluster region)
- **Certificate ARN**: `<PLACEHOLDER_REPLACE_WITH_YOUR_ACM_ARN>`
- **Domains Covered**:
  - `app.nginx.colinjcodesalot.com`
  - `app.gateway.colinjcodesalot.com`

### Creating the Certificate (If Not Already Done)

#### Option 1: Single Wildcard Certificate (Recommended for Demo)
```bash
aws acm request-certificate \
  --domain-name "*.colinjcodesalot.com" \
  --validation-method DNS \
  --region us-east-2 \
  --tags Key=Purpose,Value=gateway-migration-demo
```

#### Option 2: SAN Certificate with Specific Hostnames
```bash
aws acm request-certificate \
  --domain-name "app.nginx.colinjcodesalot.com" \
  --subject-alternative-names "app.gateway.colinjcodesalot.com" \
  --validation-method DNS \
  --region us-east-2 \
  --tags Key=Purpose,Value=gateway-migration-demo
```

### Validation
1. After requesting the certificate, retrieve validation records:
```bash
aws acm describe-certificate \
  --certificate-arn <YOUR_CERT_ARN> \
  --region us-east-2
```

2. Add the CNAME validation records to Route53
3. Wait for certificate status to become "Issued" (usually 5-10 minutes)
```bash
aws acm describe-certificate \
  --certificate-arn <YOUR_CERT_ARN> \
  --region us-east-2 \
  --query 'Certificate.Status' \
  --output text
```

## Load Balancer Configuration

### NLB Configuration via Service Annotations

Both controllers (ingress-nginx and Envoy Gateway) create their load balancers via Kubernetes `Service` resources with specific annotations. These annotations are configured in the Helm values files.

### Required Annotations for NLB with ACM TLS

```yaml
service:
  annotations:
    # Use NLB instead of CLB
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    
    # Internet-facing (not internal)
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    
    # ACM certificate ARN for TLS termination at LB
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "<YOUR_ACM_CERT_ARN>"
    
    # Enable TLS on port 443, proxy protocol on port 80
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
    
    # Backend protocol (the controllers listen on HTTP)
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
    
    # Cross-zone load balancing for better availability
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
```

### How It Works

1. **Port 443 (HTTPS)**:
   - NLB listens on 443
   - NLB terminates TLS using ACM certificate
   - NLB forwards decrypted traffic as HTTP to controller pod on port 80

2. **Port 80 (HTTP)**:
   - NLB listens on 80
   - NLB forwards HTTP to controller pod on port 80
   - (Optional: can be disabled if you want HTTPS-only)

3. **Controller Pod**:
   - Receives HTTP traffic (whether from port 80 or 443 listener)
   - Performs L7 routing based on Host header
   - Forwards to appropriate backend service

## Pre-Demo Setup Checklist

### Before Rehearsal
- [ ] Create ACM certificate for `*.colinjcodesalot.com` or specific hostnames
- [ ] Validate certificate via DNS (wait for "Issued" status)
- [ ] Update Helm values files with the ACM certificate ARN
- [ ] Note the certificate ARN for quick reference during demo

### After Installing Controllers
- [ ] Verify NLBs are created with correct annotations
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller -o yaml | grep annotations -A 10
kubectl get svc -n envoy-gateway-system -o yaml | grep annotations -A 10
```

- [ ] Verify NLBs are active in AWS Console or CLI
```bash
aws elbv2 describe-load-balancers \
  --region us-east-2 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `ingress`) || contains(LoadBalancerName, `envoy`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}'
```

- [ ] Verify listeners are configured (ports 80 and 443)
```bash
# Get NLB ARN first, then:
aws elbv2 describe-listeners \
  --load-balancer-arn <NLB_ARN> \
  --region us-east-2
```

## Testing TLS

### Test HTTPS Connectivity
```bash
# Test ingress-nginx
curl -v https://app.nginx.colinjcodesalot.com

# Test Envoy Gateway
curl -v https://app.gateway.colinjcodesalot.com
```

### Verify Certificate Details
```bash
# Check certificate issuer and validity
openssl s_client -connect app.nginx.colinjcodesalot.com:443 -servername app.nginx.colinjcodesalot.com < /dev/null 2>/dev/null | openssl x509 -noout -issuer -dates -subject
```

## Common Issues

### Issue: NLB not provisioning
- **Cause**: Insufficient IAM permissions, subnet issues, or annotation errors
- **Fix**: Check CloudFormation events, verify subnet tags, check controller logs

### Issue: TLS certificate mismatch
- **Cause**: Wrong ACM ARN, certificate not in correct region, or domains don't match
- **Fix**: Verify ARN, ensure cert is in us-east-2, check SAN/CN includes your hostnames

### Issue: Connection timeout
- **Cause**: Security groups blocking traffic
- **Fix**: Ensure NLB security groups allow inbound 80/443 from 0.0.0.0/0

### Issue: 503 Service Unavailable
- **Cause**: Target health checks failing, pods not ready
- **Fix**: Check target group health in AWS console, verify pods are running

## Webinar Talking Points

### Explain This to Attendees (1-2 minutes)
"In this demo, we're using AWS-native TLS termination because:
1. ACM certificates can't be exported from AWS
2. NLB-based TLS termination is simpler and offloads crypto from cluster
3. This is a common pattern for EKS production workloads
4. Both ingress-nginx and Envoy Gateway still perform the L7 routing—the NLB just handles the secure internet entry point

The key insight: **Ingress/Gateway is about L7 routing logic. TLS termination location is a separate architectural decision.**"

### Advanced Note
"If you needed TLS termination inside the cluster (for end-to-end encryption), you would:
- Use cert-manager with Let's Encrypt
- Store certificates as Kubernetes TLS Secrets
- Configure the controller/Gateway to reference those Secrets
- Use TLS passthrough at the LB, or TCP mode"
