# Ingress-NGINX to Envoy Gateway Migration Demo

Technical demonstration of migrating from Ingress-NGINX to Envoy Gateway (Gateway API) on Amazon EKS. Includes side-by-side deployment, canary traffic splitting, OIDC authentication, and TCP routing examples.

## Repository Structure

### `/manifests`
Kubernetes manifests for the demo environment. Includes namespace setup, application deployments (version-app, httpbin), HTTPRoutes, TCPRoutes, SecurityPolicies, and Gateway/GatewayClass configurations. Files/directories are numbered to indicate deployment order.

### `/helm`
Helm values files for Ingress-NGINX and Envoy Gateway. `ingress-nginx-values.yaml` contains AWS-specific configurations for Network Load Balancer provisioning, TLS termination, and service settings - things that are found in Gateway resource files when applied to Envoy Gateway.

### `/scripts`
Automation scripts for environment setup, controller installation, testing, and OIDC configuration. Includes scripts for traffic splitting tests and MySQL TCP connectivity verification.

### `/eks-setup`
OpenTofu/Terraform configuration for provisioning an EKS cluster with required add-ons (AWS Load Balancer Controller, EBS CSI Driver). Includes Cognito User Pool setup for OIDC authentication demos.

### `/apps`
Source code for demo applications. Contains a simple Go HTTP server (version-app) that returns version information for canary deployment testing.

## Prerequisites (Out of Scope)

This demo requires infrastructure components that must be configured outside this repository:

**DNS Configuration**: Route53 hosted zone with A records pointing to the NLB DNS names. After deploying the controllers, retrieve the LoadBalancer hostnames from the ingress-nginx-controller and Envoy Gateway services, then create A (alias) records in Route53 for `nginx.{domain}` and `gateway.{domain}`.

**TLS Certificates**: ACM certificate covering the demo hostnames. Request a wildcard certificate (`*.{domain}`) and reference the certificate ARN in the Helm values file for Ingress-NGINX, or in the EnvoyProxy configuration used by Envoy Gateway. TLS terminates at the Network Load Balancer layer, with decrypted traffic forwarded to the controllers.

## License

See [LICENSE](LICENSE) file.
