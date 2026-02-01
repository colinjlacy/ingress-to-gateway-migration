# Route53 DNS Configuration Notes

## Overview
This demo uses two separate hostnames pointing to two different AWS Load Balancers to enable side-by-side comparison of ingress-nginx and Envoy Gateway.

## Hosted Zone
- **Domain**: `colinjcodesalot.com`
- **Hosted Zone ID**: `<TO_BE_FILLED>`

## Required DNS Records

### 1. Ingress-NGINX Hostname
- **Record Name**: `app.nginx.colinjcodesalot.com`
- **Record Type**: A (Alias)
- **Target**: DNS name of the NLB created by ingress-nginx controller Service
  - Find with: `kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
- **Routing Policy**: Simple
- **Evaluate Target Health**: Yes (recommended)

### 2. Envoy Gateway Hostname
- **Record Name**: `app.gateway.colinjcodesalot.com`
- **Record Type**: A (Alias)
- **Target**: DNS name of the NLB created by Envoy Gateway data plane Service
  - Find with: `kubectl get svc -n envoy-gateway-system envoy-demo-gw-migration-demo-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
- **Routing Policy**: Simple
- **Evaluate Target Health**: Yes (recommended)

## Creating the Records

### Option 1: AWS Console
1. Navigate to Route53 → Hosted Zones → `colinjcodesalot.com`
2. Click "Create record"
3. Enter record name (e.g., `app.nginx`)
4. Toggle "Alias" to ON
5. Select "Alias to Network Load Balancer"
6. Select region: `us-east-2`
7. Select the appropriate NLB from the dropdown
8. Create record
9. Repeat for the second hostname

### Option 2: AWS CLI
```bash
# Get the ingress-nginx LB DNS name
NGINX_LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Get the Envoy Gateway LB DNS name  
ENVOY_LB=$(kubectl get svc -n envoy-gateway-system envoy-demo-gw-migration-demo-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Get the Hosted Zone ID for your NLBs (standard for us-east-2 NLBs)
NLB_HOSTED_ZONE_ID="Z3AADJGX6KTTL2"

# Create JSON for Route53 changes
cat > /tmp/route53-changes.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "app.nginx.colinjcodesalot.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${NLB_HOSTED_ZONE_ID}",
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
          "HostedZoneId": "${NLB_HOSTED_ZONE_ID}",
          "DNSName": "${ENVOY_LB}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

# Apply the changes (fill in your hosted zone ID)
YOUR_HOSTED_ZONE_ID="<YOUR_HOSTED_ZONE_ID>"
aws route53 change-resource-record-sets \
  --hosted-zone-id ${YOUR_HOSTED_ZONE_ID} \
  --change-batch file:///tmp/route53-changes.json
```

## DNS Propagation
- **Alias records** resolve directly to the target, so changes are typically visible within 60 seconds
- Test with: `dig app.nginx.colinjcodesalot.com` and `dig app.gateway.colinjcodesalot.com`
- Verify both resolve to their respective NLB addresses

## Pre-Demo Checklist
- [ ] Both DNS records created and pointing to correct NLBs
- [ ] DNS records resolve correctly from your demo location
- [ ] Test with curl to verify connectivity (after TLS is configured)

## Troubleshooting
- **Record not resolving**: Check hosted zone ID is correct
- **Wrong target**: Verify the NLB DNS names haven't changed (LBs were recreated)
- **Connection timeout**: Check security groups allow traffic from your location
