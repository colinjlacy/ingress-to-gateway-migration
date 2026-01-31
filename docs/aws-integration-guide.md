# AWS Integration Guide

This document explains all AWS integration points for the Gateway migration demo and where to configure them.

## Overview

This demo integrates with AWS services:
- **Elastic Kubernetes Service (EKS)** - Kubernetes cluster platform
- **Elastic Load Balancing v2 (NLB)** - Internet-facing load balancers
- **Certificate Manager (ACM)** - TLS certificates
- **Route53** - DNS management
- **VPC** - Networking (subnets, security groups)
- **EC2** - (Optional) Elastic IPs for static addresses

## Critical Placeholders to Replace

### 1. ACM Certificate ARN (REQUIRED)

You must replace `PLACEHOLDER_ACM_CERT_ARN` in THREE locations:

#### Location A: `demo/35-envoy-proxy-config.yaml` ⚠️ **MOST IMPORTANT**
```yaml
metadata:
  name: nlb-proxy-config
spec:
  provider:
    kubernetes:
      envoyService:
        annotations:
          service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "PLACEHOLDER_ACM_CERT_ARN"
```

**Why this is critical:** This configures the Envoy Gateway data plane Service that will provision the NLB.

#### Location B: `install/ingress-nginx-values.yaml`
```yaml
controller:
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "PLACEHOLDER_ACM_CERT_ARN"
```

**Why this is critical:** This configures the ingress-nginx controller Service that will provision the NLB.

#### Location C: `scripts/00-set-env.sh`
```bash
export ACM_CERT_ARN="PLACEHOLDER_ACM_CERT_ARN"
```

**Why useful:** The installation scripts use this to automatically substitute the ARN in temporary Helm values files.

### 2. Route53 Hosted Zone ID (For Automation)

**Location:** `demo/70-route53-dns-notes.md`

If you want to use the CLI commands to create DNS records, fill in:
```bash
YOUR_HOSTED_ZONE_ID="<YOUR_ROUTE53_HOSTED_ZONE_ID>"
```

## Optional AWS Configurations

### Subnets

**Why configure:** Control which availability zones and VPC subnets host your load balancers.

**Where to configure:**

#### For Envoy Gateway: `demo/35-envoy-proxy-config.yaml`
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-subnets: "subnet-xxxxx,subnet-yyyyy,subnet-zzzzz"
```

#### For ingress-nginx: `install/ingress-nginx-values.yaml`
```yaml
service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-subnets: "subnet-xxxxx,subnet-yyyyy,subnet-zzzzz"
```

**When to use:**
- Internal load balancers (need specific private subnets)
- Compliance requirements (load balancers must be in specific subnets)
- Cost optimization (specific AZ placement)

### Security Groups

**Why configure:** Control network access to your load balancers at the firewall level.

**Where to configure:**

#### For Envoy Gateway: `demo/35-envoy-proxy-config.yaml`
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-security-groups: "sg-xxxxx,sg-yyyyy"
  service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules: "false"
```

#### For ingress-nginx: `install/ingress-nginx-values.yaml`
```yaml
service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-security-groups: "sg-xxxxx,sg-yyyyy"
    service.beta.kubernetes.io/aws-load-balancer-manage-backend-security-group-rules: "false"
```

**When to use:**
- Specific firewall rules required
- Integration with existing security group policies
- Compliance requirements

### Elastic IPs

**Why configure:** Assign static IP addresses to your load balancers.

**Where to configure:**

#### For Envoy Gateway: `demo/35-envoy-proxy-config.yaml`
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-eip-allocations: "eipalloc-xxxxx,eipalloc-yyyyy"
```

#### For ingress-nginx: `install/ingress-nginx-values.yaml`
```yaml
service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-eip-allocations: "eipalloc-xxxxx,eipalloc-yyyyy"
```

**When to use:**
- IP whitelisting requirements
- Firewall rules based on source IP
- DNS records that can't use CNAME/Alias

**Prerequisites:**
- Allocate one EIP per subnet/AZ
- EIPs must be in the same region as your cluster

### Health Checks

**Why configure:** Customize how the load balancer determines if targets are healthy.

**Where to configure:**

#### For Envoy Gateway: `demo/35-envoy-proxy-config.yaml`
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "HTTP"
  service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "10254"
  service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: "/healthz"
  service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval: "10"
  service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout: "5"
  service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold: "2"
  service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold: "2"
```

#### For ingress-nginx: `install/ingress-nginx-values.yaml`
```yaml
service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "HTTP"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "10254"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: "/healthz"
    # ... other health check settings
```

**When to use:**
- Custom health check endpoints
- Stricter or more lenient health requirements
- Faster failover (lower intervals/thresholds)

**Default values work well for most cases.**

### Access Logs

**Why configure:** Enable load balancer access logging for debugging and compliance.

**Where to configure:**

#### For Envoy Gateway: `demo/35-envoy-proxy-config.yaml`
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-access-log-enabled: "true"
  service.beta.kubernetes.io/aws-load-balancer-access-log-s3-bucket-name: "my-bucket"
  service.beta.kubernetes.io/aws-load-balancer-access-log-s3-bucket-prefix: "nlb-logs"
```

#### For ingress-nginx: `install/ingress-nginx-values.yaml`
```yaml
service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-access-log-enabled: "true"
    service.beta.kubernetes.io/aws-load-balancer-access-log-s3-bucket-name: "my-bucket"
    service.beta.kubernetes.io/aws-load-balancer-access-log-s3-bucket-prefix: "ingress-logs"
```

**When to use:**
- Debugging connectivity issues
- Compliance/audit requirements
- Traffic analysis

**Prerequisites:**
- S3 bucket must exist
- Bucket policy must allow ELB service to write logs

### Target Group Attributes

**Why configure:** Fine-tune connection draining, stickiness, and other target behaviors.

**Where to configure:**

#### For Envoy Gateway: `demo/35-envoy-proxy-config.yaml`
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: "deregistration_delay.timeout_seconds=30,stickiness.enabled=true"
```

#### For ingress-nginx: `install/ingress-nginx-values.yaml`
```yaml
service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: "deregistration_delay.timeout_seconds=30"
```

**Common attributes:**
- `deregistration_delay.timeout_seconds=30` - Connection draining timeout
- `stickiness.enabled=true` - Enable sticky sessions
- `stickiness.type=source_ip` - Stickiness based on client IP

### Resource Tags

**Why configure:** Organize and track costs for your AWS resources.

**Where to configure:**

#### For Envoy Gateway: `demo/35-envoy-proxy-config.yaml`
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "Project=my-project,Environment=prod,CostCenter=engineering"
```

#### For ingress-nginx: `install/ingress-nginx-values.yaml`
```yaml
service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "Project=my-project,Environment=prod"
```

**Recommended tags:**
- `Project` - Project name
- `Environment` - dev/staging/prod
- `CostCenter` - For billing
- `Owner` - Team responsible

## IAM Permissions Required

The worker nodes (or the service account via IRSA) need permissions to:

### For LoadBalancer provisioning:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:AddTags",
        "ec2:DescribeInstances",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs"
      ],
      "Resource": "*"
    }
  ]
}
```

### For ACM certificate usage:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "acm:DescribeCertificate",
        "acm:ListCertificates"
      ],
      "Resource": "*"
    }
  ]
}
```

### For EIP allocation (if using):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAddresses",
        "ec2:AssociateAddress",
        "ec2:DisassociateAddress"
      ],
      "Resource": "*"
    }
  ]
}
```

## Configuration Decision Tree

### Internet-facing vs Internal?

**Internet-facing** (default in demo):
```yaml
service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
```

**Internal**:
```yaml
service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
```

Choose based on:
- **Internet-facing**: Public web services, APIs
- **Internal**: Admin interfaces, internal APIs, VPN-only access

### Which subnets?

**Let AWS choose** (default):
- Remove or comment out the `subnets` annotation
- AWS uses all subnets tagged with `kubernetes.io/role/elb=1`

**Specify explicitly**:
```yaml
service.beta.kubernetes.io/aws-load-balancer-subnets: "subnet-xxx,subnet-yyy"
```

Choose based on:
- Compliance requirements
- Cost optimization
- Specific AZ requirements

### Instance vs IP target type?

**Instance** (default):
```yaml
service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "instance"
```
- Traffic goes to node, then kube-proxy routes to pod
- Works with any CNI

**IP**:
```yaml
service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
```
- Traffic goes directly to pod IP
- Requires AWS VPC CNI
- Bypasses kube-proxy (slightly more efficient)

### External traffic policy?

**Cluster** (default in demo):
```yaml
externalTrafficPolicy: Cluster
```
- Better load distribution
- Loses client source IP

**Local**:
```yaml
externalTrafficPolicy: Local
```
- Preserves client source IP
- May have uneven distribution
- Health checks only pass on nodes with pods

Choose based on:
- **Cluster**: Default choice, simpler
- **Local**: Need client IP for logging, rate limiting, or geo-blocking

## Troubleshooting AWS Integration

### LoadBalancer stuck in pending
```bash
# Check Service events
kubectl describe svc -n <namespace> <service-name>

# Look for errors like:
# - "Could not find any suitable subnets"
# - "Security group not found"
# - "Certificate not found"
```

**Common causes:**
- Missing subnet tags
- Invalid subnet/security group IDs
- Wrong ACM certificate ARN or region
- IAM permissions issues

### TLS not working
```bash
# Verify certificate
aws acm describe-certificate --certificate-arn <ARN> --region us-east-2

# Check NLB listeners
aws elbv2 describe-listeners --load-balancer-arn <NLB-ARN>
```

**Common causes:**
- ACM certificate not in correct region
- Certificate domains don't match hostname
- Certificate not validated (status != "Issued")

### Health checks failing
```bash
# Check target health
aws elbv2 describe-target-health --target-group-arn <TG-ARN>

# Check pod logs
kubectl logs -n <namespace> <pod-name>
```

**Common causes:**
- Health check port/path incorrect
- Pods not listening on expected port
- Security groups blocking health check traffic

## Summary

### ingress-nginx AWS Configuration
- **Primary:** `install/ingress-nginx-values.yaml`
- **Override:** `demo/20-ingress-nginx-ingress.yaml` (optional)
- **Must replace:** ACM_CERT_ARN

### Envoy Gateway AWS Configuration
- **Primary:** `demo/35-envoy-proxy-config.yaml` ⚠️ **Most Important**
- **Reference:** `demo/40-gateway.yaml` (must reference EnvoyProxy)
- **Must replace:** ACM_CERT_ARN

### Both Controllers
- NLB type (not CLB)
- Internet-facing scheme
- TLS termination at load balancer
- Cross-zone load balancing enabled
- Resource tags for organization
