# ingress-nginx → Envoy Gateway (Gateway API) Migration Demo (EKS + Route53 + AWS Certificate Manager)

This document describes a **numbered, file-based demo plan** for a 40-minute webinar showing how to migrate from **ingress-nginx** to **Envoy Gateway** (Gateway API implementation) on **Amazon EKS**, using:

- **Route53** for DNS
- **AWS Certificate Manager (ACM)** for TLS certificates
- **AWS Load Balancers** (most commonly **NLB**) provisioned by `Service type=LoadBalancer`

It’s written so your team can follow along and rehearse, and so you can run it live without surprises.

---

## What this demo teaches

1. **Before:** Ingress-NGINX with an `Ingress` object handling L7 routing.
2. **After:** Envoy Gateway with `Gateway` + `HTTPRoute` handling the same routing.
3. **Safe migration:** Run both stacks side-by-side with two hostnames.
4. **Modern routing:** Traffic splitting (canary) with weighted backends.
5. **Realistic edge:** TLS via **ACM at the AWS load balancer**, with Route53 DNS pointing to that LB.

> **Important note about ACM & Gateway API**  
> ACM certificates live in AWS. You **cannot** mount an ACM cert directly as a Kubernetes TLS Secret for Envoy to terminate TLS in-cluster. In this demo, **TLS termination happens at the AWS Load Balancer (NLB/ALB)** using ACM, and the LB forwards HTTP (or TCP) to the proxy inside the cluster.

---

## Repo layout

```
demo/
  00-namespace.yaml
  10-app.yaml
  20-ingress-nginx-ingress.yaml
  30-envoy-gateway-gatewayclass.yaml
  40-gateway.yaml
  50-httproute-baseline.yaml
  60-httproute-canary.yaml
  70-route53-dns-notes.md
  80-acm-tls-and-lb-notes.md
  99-cleanup.yaml

install/
  ingress-nginx-values.yaml
  envoy-gateway-values.yaml

scripts/
  00-set-env.sh
  10-install-ingress-nginx.sh
  30-install-envoy-gateway.sh
  40-demo-status.sh
  50-demo-curl.sh

docs/
  talk-track.md
```

### Why this structure works
- `demo/` holds the **numbered demo artifacts** in the order you present them.
- TLS + Route53 are handled with **notes files** (also numbered) because they primarily involve **AWS resources/annotations** rather than Kubernetes certificate issuers.
- `install/` holds Helm values for deterministic installs.
- `scripts/` provides fast, reliable commands so you don’t free-type Helm flags on stage.
- `docs/` includes a presenter-friendly talk track.

---

## Demo prerequisites (EKS)

### Kubernetes / tooling
- EKS cluster reachable with `kubectl`
- Helm installed
- Permissions to create:
  - namespaces, deployments, services
  - Gateway API resources (`GatewayClass`, `Gateway`, `HTTPRoute`)
- A working AWS LoadBalancer provisioning path (standard on EKS)

### DNS + TLS prerequisites (AWS)
- **A Route53 hosted zone** for a domain you control, e.g. `demo.example.com`
- **An ACM certificate** validated for hostnames you will use, e.g.:
  - `app.nginx.demo.example.com`
  - `app.gateway.demo.example.com`
- You will need the **ACM certificate ARN** available during setup.

> For maximum reliability, request/validate the ACM cert **before the webinar** (and before rehearsals).

---

# Hostname strategy (side-by-side migration)

Use two hostnames that point to two different load balancers (or listeners):

- **Ingress-NGINX:** `app.nginx.demo.example.com`
- **Envoy Gateway:** `app.gateway.demo.example.com`

This allows:
- side-by-side comparisons
- incremental cutover
- no “big bang” switch during the webinar

---

# Numbered demo files

## `demo/00-namespace.yaml`

**Purpose:** Create a dedicated namespace and baseline labels.

**Fits into the project:** Keeps the demo isolated, reduces accidental collisions, makes cleanup easier.

**Includes:**
- `Namespace demo-gw-migration`

---

## `demo/10-app.yaml`

**Purpose:** Deploy a small HTTP service with **two versions** (v1 and v2) so you can demonstrate:
- routing parity between NGINX and Envoy
- header modifications
- canary (traffic splitting)

**Fits into the project:** Provides a stable backend for both ingress-nginx and Envoy Gateway.

**Recommended contents:**
- `Deployment echo-v1` and `Service echo` (stable service for v1)
- `Deployment echo-v2` and `Service echo-v2` (separate service for v2)
- A simple HTTP echo app (whoami/echo-server/http-echo) that clearly indicates version in response

**Presenter tip:** Ensure the response body includes something like `version=v1` or `version=v2` so you can count splits with a loop.

---

## `demo/20-ingress-nginx-ingress.yaml`

**Purpose:** Define the “before” state using Kubernetes `Ingress` with `ingressClassName: nginx`.

**Fits into the project:** Baseline configuration you will migrate off of.

**Recommended behavior:**
- Host: `app.nginx.demo.example.com`
- Path: `/` → `Service echo` (v1)
- Keep it minimal: no complex rewrites/auth in the baseline

**Optional (nice-to-have):**
- Add one lightweight annotation like a header add (but don’t overdo it—annotations can become a rabbit hole live).

---

## `demo/30-envoy-gateway-gatewayclass.yaml`

**Purpose:** Ensure a `GatewayClass` exists and is named consistently.

**Fits into the project:** Makes the “implementation vs model” separation explicit to attendees.

**Note:** Many Envoy Gateway installs create a default GatewayClass automatically. Keep this file for documentation/consistency even if it is redundant.

---

## `demo/40-gateway.yaml`

**Purpose:** Create the **Gateway** (the entry point) with an HTTP listener.

**Fits into the project:** Replaces the conceptual role of “Ingress controller + Ingress resource” with a more explicit model:
- listeners
- route attachment rules

**Recommended contents:**
- `Gateway` named `demo-gateway`
- Listener on port 80, protocol HTTP
- `allowedRoutes` limited to same namespace

---

## `demo/50-httproute-baseline.yaml`

**Purpose:** Attach `HTTPRoute` to the Gateway to route the Envoy hostname to the same backend.

**Fits into the project:** This is the “Ingress parity” step, but expressed via Gateway API.

**Recommended behavior:**
- Host: `app.gateway.demo.example.com`
- PathPrefix `/` → `Service echo` (v1)

**Recommended “wow” marker:**
- Add a `RequestHeaderModifier` filter to inject a header like:
  - `x-demo-edge: envoy-gateway`
so you can show instantly: same backend, new edge stack.

---

## `demo/60-httproute-canary.yaml`

**Purpose:** Demonstrate **traffic splitting** using weighted backendRefs.

**Fits into the project:** Shows a structured, readable API approach that replaces controller-specific tricks.

**Recommended behavior:**
- 90 weight → `Service echo` (v1)
- 10 weight → `Service echo-v2` (v2)

**How you’ll demo it:**
- Run 30–50 curls and count versions.

---

## `demo/70-route53-dns-notes.md`

**Purpose:** Document the Route53 DNS records required for the demo.

**Fits into the project:** DNS is critical for a smooth demo, but is often done outside Kubernetes.

**Include:**
- Hosted zone name
- The two record names
- Whether you’ll use Alias records to the LB DNS name
- Notes on TTL and propagation

**Recommended approach for reliability:**
- Use Route53 **Alias A records** pointing at each LB’s DNS name.
- Keep TTL low (Route53 alias doesn’t use TTL the same way, but keep the principle: avoid long caching in clients/proxies).

---

## `demo/80-acm-tls-and-lb-notes.md`

**Purpose:** Document how TLS works in this demo using **ACM + AWS Load Balancers**, and what annotations/values you use.

**Fits into the project:** This is where you explain and configure the “realistic edge” story:
- public HTTPS endpoint
- AWS terminates TLS using ACM
- forwards HTTP to the in-cluster proxy

### Recommended TLS architecture for the webinar
- Use **NLB with TLS listener** + ACM cert
- NLB forwards to the controller Service on port 80 (HTTP) or TCP depending on your setup
- The proxy (nginx/envoy) still performs **L7 routing by Host header**

### Where you configure it
You generally configure TLS-on-LB in one of two ways:
1. **Service annotations** for the controller Service (most common), or
2. Helm values that apply those annotations to the controller Service.

This repo keeps those in:
- `install/ingress-nginx-values.yaml`
- `install/envoy-gateway-values.yaml`

### What you should capture in this notes file
- Which LB type you’re using (NLB recommended)
- Whether it’s internet-facing or internal
- The ACM certificate ARN(s)
- Which ports are exposed (80 and/or 443)
- Any required annotations for:
  - LB type
  - TLS cert ARN
  - SSL ports
  - backend protocol
  - cross-zone behavior

> Tip: In the webinar, explicitly state:  
> “Ingress/Gateway is L7 inside the cluster; AWS NLB is providing the secure internet-facing entry point.”

---

## `demo/99-cleanup.yaml`

**Purpose:** Remove all demo resources so you can rehearse repeatedly.

**Fits into the project:** Lets you reset quickly and avoid drift between runs.

**Recommended behavior:**
- Delete the demo namespace (fastest), OR
- Delete resources explicitly if you want to preserve the namespace

---

# Installation files (Helm values)

## `install/ingress-nginx-values.yaml`

**Purpose:** Deterministic install settings for ingress-nginx on EKS.

**Fits into the project:** Ensures the controller Service is created consistently and annotated to provision the expected AWS LB behavior.

**Should include (at minimum):**
- controller Service `type: LoadBalancer`
- AWS LB annotations for your chosen LB type (NLB recommended)
- Optional:
  - `externalTrafficPolicy: Local` if you want client IP preservation (be prepared to explain tradeoffs)

**TLS with ACM (if terminating at NLB):**
- Include annotations/values that attach the ACM certificate ARN and enable the 443 listener.

---

## `install/envoy-gateway-values.yaml`

**Purpose:** Deterministic install settings for Envoy Gateway on EKS.

**Fits into the project:** Controls how the Envoy data plane Service is exposed (LoadBalancer) and how the AWS LB is configured.

**Should include (at minimum):**
- Data plane Service `type: LoadBalancer`
- AWS LB annotations (NLB) and optional TLS configuration (ACM cert ARN)

---

# Scripts (for webinar safety)

## `scripts/00-set-env.sh`
**Purpose:** One place to define:
- namespace
- hostnames
- ACM cert ARN
- any common kubectl/helm settings

**Fits into the project:** Prevents typos and keeps your commands consistent during the webinar.

---

## `scripts/10-install-ingress-nginx.sh`
**Purpose:** Install ingress-nginx using the repo values file and wait for readiness.

**Fits into the project:** Fast, repeatable setup with predictable LB provisioning.

---

## `scripts/30-install-envoy-gateway.sh`
**Purpose:** Install Envoy Gateway using the repo values file and wait for readiness.

**Fits into the project:** Ensures Gateway API controller + data plane are ready before applying Gateway resources.

---

## `scripts/40-demo-status.sh`
**Purpose:** Print a “demo dashboard”:
- key Pods ready?
- Services have EXTERNAL-IP / hostname?
- Gateway conditions (Accepted/Programmed)?

**Fits into the project:** Lets you quickly recover if something is off, without hunting through namespaces.

---

## `scripts/50-demo-curl.sh`
**Purpose:** Run the main verification curls:
- NGINX HTTP/HTTPS
- Envoy HTTP/HTTPS
- Canary split loop

**Fits into the project:** Reduces typing and ensures you show consistent output.

---

# Suggested apply/install order (webinar runbook)

### 1) Apply baseline namespace + app
```bash
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/10-app.yaml
```

### 2) Install ingress-nginx
```bash
./scripts/10-install-ingress-nginx.sh
kubectl apply -f demo/20-ingress-nginx-ingress.yaml
```

### 3) Install Envoy Gateway and apply Gateway API resources
```bash
./scripts/30-install-envoy-gateway.sh
kubectl apply -f demo/30-envoy-gateway-gatewayclass.yaml
kubectl apply -f demo/40-gateway.yaml
kubectl apply -f demo/50-httproute-baseline.yaml
kubectl apply -f demo/60-httproute-canary.yaml
```

### 4) Configure Route53 + ACM TLS (pre-demo or between segments)
- Follow:
  - `demo/70-route53-dns-notes.md`
  - `demo/80-acm-tls-and-lb-notes.md`

> In a live webinar, you typically **pre-create** the Route53 records and ACM cert.  
> Then you only “reveal” them during the demo (show the LB and that HTTPS works).

### 5) Cleanup
```bash
kubectl apply -f demo/99-cleanup.yaml
# OR
kubectl delete ns demo-gw-migration
```

---

# Presenter notes (recommended)

## `docs/talk-track.md`
Keep this tight and aligned to the milestones:
1. Before: Ingress
2. Install Envoy Gateway
3. Gateway + HTTPRoute parity
4. Canary
5. TLS at LB with ACM + Route53
6. Cutover plan + pitfalls

---

# Common pitfalls to call out (1–2 minutes each)

- **ACM vs in-cluster TLS:** ACM is AWS-managed; termination is usually at AWS LB.
- **NLB is L4:** Host/path routing still happens in NGINX/Envoy after the LB forwards HTTP.
- **Client IP:** depends on LB type + `externalTrafficPolicy` + proxy config.
- **Parity gaps:** NGINX annotations don’t map 1:1; you’ll use Gateway API filters/policies and sometimes external auth services.

---

## Questions I would ask if we were making this fully “drop-in runnable”

You don’t need to answer these for the plan to be useful, but they determine the exact annotations/values:
1. Are you standardizing on **NLB** for both controllers, or do you want ALB for one of them?
2. Should the LBs be **internet-facing** or **internal**?
3. Do you want to preserve **client source IP** (and discuss `externalTrafficPolicy: Local`), or keep it simpler?
