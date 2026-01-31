# Gateway Migration Demo - Talk Track

**Duration:** 40 minutes  
**Audience:** DevOps engineers, Platform engineers, SREs  
**Objective:** Show how to migrate from ingress-nginx to Envoy Gateway using Gateway API on AWS EKS

---

## Introduction (3 minutes)

### Opening Hook
"Today we're going to walk through a real-world migration: moving from ingress-nginx to Envoy Gateway using the Kubernetes Gateway API. We'll do this live on AWS EKS, showing you how to run both stacks side-by-side, validate parity, and demonstrate modern traffic management capabilities."

### What We'll Cover
1. The current state: ingress-nginx with the `Ingress` resource
2. Installing and configuring Envoy Gateway
3. Achieving routing parity with Gateway API (`Gateway` + `HTTPRoute`)
4. Advanced routing: canary deployments with weighted traffic splitting
5. TLS at the edge using ACM and Network Load Balancers
6. Migration strategy and common pitfalls

### Demo Environment
- **Platform:** Amazon EKS in us-east-2
- **Application:** Istio Bookinfo (without Istio - just the microservices)
- **DNS:** Route53 with two hostnames for side-by-side comparison
- **TLS:** AWS Certificate Manager + Network Load Balancers
- **Two entry points:**
  - `app.nginx.colinjcodesalot.com` → ingress-nginx
  - `app.gateway.colinjcodesalot.com` → Envoy Gateway

---

## Part 1: The "Before" State - ingress-nginx (8 minutes)

### Talking Points
"Let's start by looking at what most teams have today: ingress-nginx routing traffic to our application."

### Demo Steps

#### 1. Show the application (2 min)
```bash
# Source our environment
source scripts/00-set-env.sh

# Show the running app
kubectl get pods -n demo-gw-migration
kubectl get svc -n demo-gw-migration
```

**Say:**
"We're running the Bookinfo application with multiple microservices:
- **productpage** - the main entry point
- **reviews** - we have two versions (v1 without stars, v2 with black stars)
- **details** and **ratings** - supporting services

This gives us a realistic multi-service app to demonstrate routing capabilities."

#### 2. Show ingress-nginx installation (2 min)
```bash
# Show the Helm values
cat install/ingress-nginx-values.yaml
```

**Say:**
"Notice a few key configurations here:
- We're using an AWS Network Load Balancer (NLB)
- TLS termination happens at the NLB using AWS Certificate Manager
- The NLB forwards HTTP traffic to our controller on port 80
- The controller still does all the L7 routing - host-based, path-based, etc."

**Optional (if time permits):**
Briefly mention that the ingress-nginx values are clean and simple. The complexity shows up in the Ingress resource itself (which you'll show next).

#### 3. Show the Ingress resource (3 min) **KEY MOMENT**
```bash
# Show the Ingress file
cat demo/20-ingress-nginx-ingress.yaml | less
```

**Say:**
"Now let's look at the Ingress resource. This is what happens in real production environments..."

**[Scroll through the file slowly]**

"Notice what we have here:
- Over 300 lines for a simple application
- Four different teams' routes all in one file
- Conflicting requirements in the annotations:
  - Product team wants 60s timeout
  - Catalog team wants 15s timeout  
  - Compromise: 45s - nobody's happy
- CORS enabled globally even though only one service needs it
- Session affinity forced on all services, even stateless ones
- Comments trying to track ownership: 'Added by X team', 'TODO: remove after...'
- Legacy paths that can't be deleted because 'someone might be using it'
- Warning comments: 'DO NOT REMOVE' and 'See JIRA-856 for context'

**[Scroll to the bottom]**

"And here's my favorite part - the 'KNOWN ISSUES' section listing all the problems teams have documented but can't fix without breaking other teams' services.

This is technical debt in action. Every team adding their requirements, but the annotations apply globally. You can't customize per-service without creating multiple Ingress resources, which becomes its own maintenance nightmare.

**Who wants to be on-call for this configuration?**"

**[Pause for effect]**

"This is the reality Ingress teams face. It works, but it doesn't scale well organizationally."

#### 4. Test it live (2 min)
```bash
# Use our demo script
./scripts/50-demo-curl.sh
```

**Say:**
"Let's verify it works. You can see:
- The application is responding
- Our custom header is present: `X-Demo-Edge: ingress-nginx`
- TLS is working via ACM at the load balancer"

---

## Part 2: Installing Envoy Gateway (5 minutes)

### Talking Points
"Now let's install Envoy Gateway alongside our existing setup. This is the beauty of the side-by-side approach - no big bang migration, no downtime."

### Demo Steps

#### 1. Explain Gateway API (2 min)

**Say:**
"Gateway API is the next generation of Ingress. It's:
- **Role-oriented:** Separates concerns between platform operators and developers
- **Expressive:** Native support for header matching, traffic splitting, and more
- **Extensible:** Designed for multiple implementations
- **Portable:** Works across different gateway implementations

Key resources:
- **GatewayClass** - Defines the gateway implementation (like IngressClass)
- **Gateway** - The actual load balancer/proxy instance with listeners
- **HTTPRoute** - Routes traffic to services (like Ingress, but more powerful)"

#### 2. Install Envoy Gateway (3 min)
```bash
# Run the installation script
./scripts/30-install-envoy-gateway.sh
```

**Say:**
"Our installation script:
1. Installs Gateway API CRDs if needed
2. Installs Envoy Gateway controller
3. Configures the same NLB + ACM setup as ingress-nginx

Watch as it provisions... [wait for completion]

Notice that we have:
- A controller running in the `envoy-gateway-system` namespace
- But no data plane yet - that gets created when we apply a Gateway resource
- This separation of control and data plane is a key Gateway API concept"

---

## Part 3: Achieving Parity with Gateway API (12 minutes)

### Talking Points
"Now we'll create Gateway API resources that replicate our ingress-nginx routing."

### Demo Steps

#### 1. Apply EnvoyProxy, GatewayClass and Gateway (3 min)
```bash
# Show the EnvoyProxy configuration
cat demo/35-envoy-proxy-config.yaml
```

**Say:**
"First, we need to configure how the Envoy data plane will be deployed. The EnvoyProxy resource defines:
- The Service type (LoadBalancer)
- AWS-specific annotations for NLB provisioning
- ACM certificate for TLS termination
- All the AWS integration points

This is a key difference from ingress-nginx: Gateway API separates the data plane configuration from the routing rules."

```bash
# Apply the EnvoyProxy config
kubectl apply -f demo/35-envoy-proxy-config.yaml

# Show the GatewayClass
cat demo/30-envoy-gateway-gatewayclass.yaml

# Apply it
kubectl apply -f demo/30-envoy-gateway-gatewayclass.yaml

# Show the Gateway
cat demo/40-gateway.yaml

# Apply it
kubectl apply -f demo/40-gateway.yaml

# Check status
kubectl get gateway -n demo-gw-migration
kubectl describe gateway demo-gateway -n demo-gw-migration
```

**Say:**
"The Gateway resource is like deploying a dedicated proxy instance:
- It references our GatewayClass (the implementation)
- Defines an HTTP listener on port 80
- Specifies which routes can attach (same namespace only)

When we apply this, Envoy Gateway:
1. Creates an Envoy proxy deployment
2. Creates a Service of type LoadBalancer
3. AWS provisions an NLB with our ACM certificate

Let's check the status... [show gateway status]

Look at the conditions:
- **Accepted:** The Gateway is valid
- **Programmed:** The data plane is configured and ready"

#### 2. Create the HTTPRoutes (5 min) **KEY MOMENT**
```bash
# Show the separated HTTPRoute files
ls demo/5*-httproute-*.yaml
```

**Say:**
"Instead of one giant Ingress file, we now have separate HTTPRoute files:
- 50: Product team (productpage)
- 51: Catalog team (details)
- 52: Reviews team (reviews + beta)
- 53: Analytics team (ratings)

Let's look at a couple..."

```bash
# Show productpage route
cat demo/50-httproute-baseline.yaml
```

**Say:**
"The Product team's route is clean and focused:
- Clear ownership labels
- Only their service routes
- Adding custom headers with filters
- About 50 lines total

Compare this to the 300+ line Ingress where all teams were mixed together."

```bash
# Show details route
cat demo/51-httproute-details.yaml
```

**Say:**
"Now the Catalog team's route:
- They own this file completely
- Look at the commented policy examples at the bottom
- They can set a 15-second timeout without affecting Reviews team
- Legacy API paths are clearly marked with deprecation warnings

**This is the key insight**: Each team gets their own configuration file. No more merge conflicts. No more compromise settings. No more 'I don't know who added this annotation three years ago.'"

```bash
# Apply all the routes
kubectl apply -f demo/50-httproute-baseline.yaml
kubectl apply -f demo/51-httproute-details.yaml
kubectl apply -f demo/52-httproute-reviews.yaml
kubectl apply -f demo/53-httproute-ratings.yaml

# Check status
kubectl get httproute -n demo-gw-migration
```

**Say:**
"Each HTTPRoute attaches to the same Gateway. The Gateway is platform infrastructure. The routes are team-owned application configuration.

**Separation of concerns in action.**"

#### 3. Get the LoadBalancer and configure DNS (3 min)
```bash
# Get the data plane service
kubectl get svc -n envoy-gateway-system

# Show DNS configuration guide
cat demo/70-route53-dns-notes.md | head -30
```

**Say:**
"Now we have a second NLB for Envoy Gateway. In Route53, we create:
- An A (Alias) record for `app.gateway.colinjcodesalot.com`
- Pointing to the new NLB DNS name

[Show in AWS Console or CLI if time permits]

This gives us two parallel entry points - we can test both independently."

#### 4. Test parity (2 min)
```bash
# Use status script
./scripts/40-demo-status.sh

# Test both endpoints
curl -I http://app.nginx.colinjcodesalot.com/
curl -I http://app.gateway.colinjcodesalot.com/
```

**Say:**
"Perfect! Both are working:
- Same application backend
- Same TLS setup at the NLB
- Different proxies and routing APIs
- Notice the different `X-Demo-Edge` headers proving which path the traffic took

We've achieved parity - now let's show what Gateway API enables."

---

## Part 4: Advanced Routing - Canary Deployment (8 minutes)

### Talking Points
"Now for the 'wow' moment: weighted traffic splitting with no annotations, no custom CRDs - just standard Gateway API."

### Demo Steps

#### 1. Explain the canary scenario (2 min)

**Say:**
"We have two versions of our reviews service:
- **v1:** No star ratings
- **v2:** Shows black star ratings

We want to:
- Send 90% of traffic to v1 (stable)
- Send 10% of traffic to v2 (canary)
- Do this declaratively with standard API resources"

#### 2. Show and apply the canary HTTPRoute (3 min)
```bash
# Show the canary route
cat demo/60-httproute-canary.yaml
```

**Say:**
"Look at the `backendRefs` section:
- Two backends: `reviews` (v1) and `reviews-v2`
- Weights: 90 and 10
- That's it! No controller-specific annotations

This is portable - the same YAML works with any Gateway API implementation."

```bash
# Apply the canary route
kubectl apply -f demo/60-httproute-canary.yaml

# Verify
kubectl get httproute bookinfo-canary -n demo-gw-migration -o yaml
```

#### 3. Test the traffic split (3 min)
```bash
# Run traffic test
./scripts/50-demo-curl.sh
```

**Say:**
"Let's send multiple requests and count the distribution...

[Show results]

You can see the approximate 90/10 split. In production, you would:
1. Start with 95/5 or 99/1
2. Monitor metrics and error rates
3. Gradually increase canary traffic
4. Roll back instantly if issues arise - just update the weights"

**Optional advanced talking point:**
"Note: The Bookinfo app's internal calls from productpage to reviews happen directly service-to-service. To fully control internal routing, you'd typically use a service mesh like Istio or Linkerd alongside Gateway API for north-south traffic."

---

## Part 5: TLS and AWS Integration (3 minutes)

### Talking Points
"Let's talk about how TLS works in this setup - it's a common point of confusion."

### Demo Steps

#### 1. Explain the architecture (2 min)

**Say:**
"Our TLS architecture:
```
Internet (HTTPS) → NLB (TLS termination with ACM cert) → HTTP → Envoy/NGINX → HTTP → App
```

Why this approach?
1. **ACM certificates can't be exported** from AWS
2. **NLB-based termination** is simple and offloads crypto work
3. **Common in EKS production** deployments

The key insight: **Gateway/Ingress is about L7 routing logic. TLS termination is a separate decision.**

If you needed end-to-end encryption:
- Use cert-manager with Let's Encrypt
- Store certs as Kubernetes Secrets
- Configure TLS in the Gateway/Ingress resource
- Use TLS passthrough or TCP mode at the LB"

#### 2. Show the configuration (1 min)
```bash
# Show the ACM configuration notes
cat demo/80-acm-tls-and-lb-notes.md | head -50
```

**Say:**
"All the details are documented here:
- How to create and validate the ACM certificate
- Required Service annotations for NLB + TLS
- How listeners are configured
- Troubleshooting common issues"

---

## Part 6: Migration Strategy & Pitfalls (3 minutes)

### Talking Points

#### Migration Strategy
**Say:**
"Based on what we've shown, here's a pragmatic migration path:

**Phase 1: Preparation**
1. Install Envoy Gateway in your cluster
2. Create Gateway resources in test namespaces
3. Validate HTTPRoute behavior matches your Ingress rules

**Phase 2: Side-by-Side**
1. Create a new hostname (like we did with `app.gateway.*`)
2. Apply Gateway + HTTPRoute for your services
3. Run both stacks in production
4. Validate metrics, logs, and performance

**Phase 3: Gradual Cutover**
1. Switch DNS for one service at a time
2. Monitor closely for issues
3. Keep ingress-nginx as fallback

**Phase 4: Complete Migration**
1. Move all services to Gateway API
2. Decommission ingress-nginx
3. Update runbooks and documentation"

#### Common Pitfalls
**Say:**
"Watch out for these gotchas:

1. **Annotation Migration:**
   - NGINX annotations don't automatically convert
   - Research Gateway API alternatives (policies, filters)
   - Some features may need external auth services

2. **Client IP Preservation:**
   - Depends on `externalTrafficPolicy` setting
   - `Local` preserves IPs but affects distribution
   - `Cluster` (default) is simpler but loses source IP

3. **TLS Configuration:**
   - ACM is AWS-only, can't export certs
   - In-cluster TLS needs cert-manager
   - Don't mix approaches without planning

4. **Gateway API Versions:**
   - Gateway API is maturing rapidly
   - Pin CRD versions in production
   - Test upgrades in staging

5. **Feature Parity:**
   - Not everything in NGINX has Gateway API equivalent yet
   - Check your specific features against Gateway API spec
   - Extensibility via policy attachments is growing"

---

## Closing (2 minutes)

### Summary
**Say:**
"Let's recap what we've covered:

✅ Migrated from Ingress to Gateway API  
✅ Ran both stacks side-by-side safely  
✅ Achieved routing parity  
✅ Demonstrated advanced traffic splitting  
✅ Integrated with AWS services (ACM, NLB, Route53)  

**Key takeaways:**
1. Gateway API is production-ready and offers significant advantages
2. Side-by-side migration reduces risk
3. Standard APIs enable better tooling and portability
4. AWS integration is straightforward with proper configuration

**Resources:**
- This demo repo: [your repo URL]
- Gateway API docs: https://gateway-api.sigs.k8s.io/
- Envoy Gateway docs: https://gateway.envoyproxy.io/"

### Q&A Setup
**Say:**
"That's our demo! Let's open it up for questions. Common questions I get:
- How does Gateway API compare to Istio?
- What about other implementations like Cilium or Kong?
- How do you handle auth and rate limiting?
- What's the performance difference?

Who has the first question?"

---

## Backup Slides/Talking Points (If Needed)

### If Asked About Other Implementations
"Gateway API has many implementations:
- **Envoy Gateway** (what we showed)
- **Istio** (service mesh + ingress)
- **Cilium** (eBPF-based)
- **Kong** (API gateway features)
- **NGINX Gateway Fabric** (NGINX's official Gateway API implementation)
- **Traefik**, **HAProxy**, and others

The beauty is: the same HTTPRoute YAML works across all of them (for standard features)."

### If Asked About Service Mesh
"Gateway API handles **north-south** (ingress) traffic. For **east-west** (service-to-service):
- Use a service mesh like Istio or Linkerd
- Gateway API has a 'GAMMA' initiative for mesh use cases
- Many organizations use Gateway API + mesh together"

### If Asked About Cost
"Cost considerations:
- Both controllers have similar resource requirements
- NLB costs are the same regardless of controller
- Envoy Gateway may use slightly more memory per proxy
- At scale, operational simplicity may save more than infrastructure costs"

---

## Troubleshooting During Demo

### If DNS isn't resolving
```bash
# Check propagation
dig app.gateway.colinjcodesalot.com

# Fallback: Use curl with Host header
curl -H "Host: app.gateway.colinjcodesalot.com" http://<NLB-DNS-NAME>/
```

### If Gateway isn't ready
```bash
# Check Gateway status
kubectl describe gateway demo-gateway -n demo-gw-migration

# Check Envoy logs
kubectl logs -n envoy-gateway-system -l app.kubernetes.io/name=envoy-gateway --tail=50
```

### If LoadBalancer is stuck
```bash
# Check service events
kubectl describe svc -n envoy-gateway-system

# Check AWS LoadBalancer Controller logs (if installed)
# Otherwise, NLBs should provision automatically via cloud-controller-manager
```

---

## Post-Demo Cleanup

After the webinar:
```bash
# Delete demo resources
kubectl delete ns demo-gw-migration

# Uninstall controllers
helm uninstall ingress-nginx -n ingress-nginx
helm uninstall envoy-gateway -n envoy-gateway-system

# Delete namespaces
kubectl delete ns ingress-nginx
kubectl delete ns envoy-gateway-system

# Delete Route53 records (AWS Console or CLI)
# Keep ACM certificate if reusable for other demos
```
