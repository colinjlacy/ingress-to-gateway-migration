# Routes Comparison: Ingress vs Gateway API

This document explains the key differences between the single Ingress file and the multiple HTTPRoute files.

## The Problem: Monolithic Ingress Configuration

**File:** `demo/20-ingress-nginx-ingress.yaml`

### Issues Demonstrated

1. **Single Point of Contention**
   - All teams' routes in one file
   - Merge conflicts on every PR
   - No clear ownership boundaries
   - Changes affect everyone

2. **Global Annotations**
   - Timeout settings are a compromise between teams
   - CORS enabled for all services (only one team needs it)
   - Session affinity forces statefulness on stateless services
   - Rate limiting applies to health checks and metrics
   - Can't customize per-service without creating multiple Ingress resources

3. **Configuration Archaeology**
   - Comments try to explain ownership
   - "Last modified" notes get stale
   - Jira ticket references for context
   - TODO items that never get done
   - Warning comments about what not to touch

4. **Technical Debt Accumulates**
   - Legacy paths that can't be removed
   - Workarounds for missing features
   - Annotations that apply globally when they shouldn't
   - Security concerns (CORS, rate limiting, IP whitelist)

5. **Testing is Risky**
   - Any change affects all paths
   - No dry-run validation
   - Production incidents: INCIDENT-2847, INCIDENT-3012, INCIDENT-3156

## The Solution: Separated HTTPRoutes

**Files:**
- `demo/50-httproute-baseline.yaml` - Product team (productpage)
- `demo/51-httproute-details.yaml` - Catalog team (details)
- `demo/52-httproute-reviews.yaml` - Reviews team (reviews + beta)
- `demo/53-httproute-ratings.yaml` - Analytics team (ratings)
- `demo/60-httproute-canary.yaml` - Platform team (canary testing)

### Benefits Demonstrated

#### 1. Clear Ownership
```yaml
metadata:
  labels:
    team: catalog-team
    service: details
  annotations:
    owner: catalog-team@example.com
```

Each HTTPRoute is owned by a specific team. No confusion, no merge conflicts between teams.

#### 2. Independent Configuration

**Details team** (fast service):
```yaml
# Can have 15s timeout (commented policy example)
timeout:
  http:
    requestTimeout: 15s
```

**Reviews team** (complex processing):
```yaml
# Can have 60s timeout - no compromise needed
timeout:
  http:
    requestTimeout: 60s
```

**In the Ingress**: Timeout was set to 45s, making nobody happy.

#### 3. Service-Specific Policies

**Reviews needs CORS**:
```yaml
# CORS policy attached only to reviews-route
cors:
  allowOrigins:
  - "https://bookinfo-frontend.example.com"
  allowCredentials: true
```

**Ratings doesn't need CORS**: No policy attached. Simple and secure.

**In the Ingress**: CORS was enabled globally for all services.

#### 4. Selective Features

**Ratings is stateless**:
```yaml
loadBalancer:
  type: Random  # No session affinity!
```

**Reviews may need stickiness** (in the future):
```yaml
loadBalancer:
  type: ConsistentHash
```

**In the Ingress**: Session affinity was forced on all services.

#### 5. Advanced Routing

**Reviews can use header-based routing**:
```yaml
matches:
- path:
    type: PathPrefix
    value: /reviews
  headers:
  - name: X-Beta-User
    value: "true"
```

**Ratings can use query parameter matching**:
```yaml
matches:
- path:
    type: PathPrefix
    value: /ratings
  queryParams:
  - type: Exact
    name: version
    value: "2"
```

**In the Ingress**: Complex regex rewrites and configuration snippets required.

#### 6. Isolated Testing and Deployment

Each team can:
- Deploy their HTTPRoute independently
- Test changes without affecting others
- Roll back their route without touching others
- Use GitOps with separate pipelines

## Side-by-Side Comparison

### Timeouts

#### Ingress (Compromise)
```yaml
# WARNING: Reviews team needs 60s, but Details team complains about slow clients
# Compromise set to 45s - neither team is happy
nginx.ingress.kubernetes.io/proxy-read-timeout: "45"
```

#### Gateway API (Per-Service)
```yaml
# details-route: 15s (fast service)
# reviews-route: 60s (complex processing)
# ratings-route: 30s (standard)
# Each team gets what they need!
```

### CORS

#### Ingress (Global)
```yaml
# CORS configuration - added for frontend team
# TODO: Ratings team doesn't need CORS, but it applies to everything now
nginx.ingress.kubernetes.io/enable-cors: "true"
nginx.ingress.kubernetes.io/cors-allow-origin: "https://bookinfo-frontend.example.com,https://partner-app.example.com"
```

#### Gateway API (Selective)
```yaml
# Only attached to reviews-route via SecurityPolicy
# Other services don't have CORS headers
# More secure and performant
```

### Session Affinity

#### Ingress (Forced on Everyone)
```yaml
# Session affinity - enabled by Product team for Reviews
# Side effect: all services now have sticky sessions (not always desired)
nginx.ingress.kubernetes.io/affinity: "cookie"
```

#### Gateway API (Per-Service Choice)
```yaml
# reviews-route: Can have session affinity if needed
# ratings-route: No affinity (stateless)
# Each service configured appropriately
```

### Rate Limiting

#### Ingress (Global Problem)
```yaml
# Rate limiting - added by SRE team after incident-2847
# Reviews team requested exemption but annotations don't support per-path limits
nginx.ingress.kubernetes.io/limit-rps: "100"
```

**Problem**: Health checks and metrics also get rate limited during incidents!

#### Gateway API (Flexible)
```yaml
# reviews-route: 100 req/s (high traffic)
# details-route: 200 req/s (lightweight)
# ratings-route: 50 req/s (analytics)
# Health/metrics routes: No rate limit
```

### Security (IP Whitelisting)

#### Ingress (All or Nothing)
```yaml
# Whitelist configuration - requested by Security team for /admin paths
# TODO: Make this path-specific when NGINX supports it better
# nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,172.16.0.0/12"
```

**Problem**: Applies to entire Ingress, not just /admin paths.

#### Gateway API (Targeted)
```yaml
# SecurityPolicy attached only to ratings-webhook-route
# Other routes unaffected
ipAllowlist:
- 203.0.113.0/24  # Partner system only
```

## Migration Strategy Benefits

### Phase 1: Side-by-Side
- Keep Ingress running (app.nginx.colinjcodesalot.com)
- Deploy HTTPRoutes (app.gateway.colinjcodesalot.com)
- Both systems serving traffic independently
- **Zero risk** to production

### Phase 2: Per-Service Migration
- Migrate one service at a time
- Update DNS to point to Gateway API endpoint
- Monitor and validate
- **Incremental, controlled rollout**

### Phase 3: Team Empowerment
- Each team owns their HTTPRoute
- Platform team manages Gateway infrastructure
- **Clear separation of concerns**

## File Structure Recommendations

### Option A: One HTTPRoute per Service (This Demo)
```
50-httproute-baseline.yaml     # productpage
51-httproute-details.yaml      # details
52-httproute-reviews.yaml      # reviews
53-httproute-ratings.yaml      # ratings
```

**Pros:**
- Clear ownership per file
- Easy to apply/rollback per service
- GitOps friendly (separate pipelines)

**Cons:**
- More files to manage
- Need to understand parent Gateway reference

### Option B: One HTTPRoute per Team
```
50-httproute-product-team.yaml   # All product team routes
51-httproute-catalog-team.yaml   # All catalog team routes
```

**Pros:**
- Team-centric organization
- Fewer files
- Team can manage all their routes together

**Cons:**
- Teams with multiple services have larger files
- Still better than monolithic Ingress

### Option C: Hybrid (Recommended for Large Deployments)
```
routes/
  product-team/
    productpage-route.yaml
    admin-route.yaml
  catalog-team/
    details-route.yaml
  reviews-team/
    reviews-stable-route.yaml
    reviews-beta-route.yaml
  analytics-team/
    ratings-route.yaml
```

**Pros:**
- Clear directory ownership
- Scales to many services
- Perfect for GitOps with path-based automation

## Demo Talking Points

### Show the Ingress File First
1. Scroll through the 300+ lines
2. Point out the conflicting comments
3. Highlight the "KNOWN ISSUES" section at the bottom
4. Ask: "Who owns the timeout setting? What happens if Product team needs to change it?"

### Then Show the HTTPRoute Files
1. Much shorter, focused files
2. Each has clear ownership labels
3. No conflicting requirements
4. Point out commented policy examples
5. Ask: "Which would you rather debug at 2 AM?"

### The "Aha Moment"
**With Ingress**: "We can't give Details team their 15s timeout without affecting Reviews team."

**With Gateway API**: "Each team configures their own timeout. Platform team provides the Gateway, teams provide their routes."

## Testing the Routes

```bash
# Test all services via Ingress (monolithic config)
curl http://app.nginx.colinjcodesalot.com/details
curl http://app.nginx.colinjcodesalot.com/reviews
curl http://app.nginx.colinjcodesalot.com/ratings

# Test all services via Gateway API (separated configs)
curl http://app.gateway.colinjcodesalot.com/details
curl http://app.gateway.colinjcodesalot.com/reviews
curl http://app.gateway.colinjcodesalot.com/ratings

# Same functionality, better architecture
```

## Conclusion

The **Ingress approach** leads to:
- ❌ Configuration sprawl in a single file
- ❌ Conflicting team requirements
- ❌ Global annotations affecting everyone
- ❌ Risky deployments (one change affects all)
- ❌ Technical debt accumulation
- ❌ Ownership confusion

The **Gateway API approach** enables:
- ✅ Clear ownership boundaries
- ✅ Service-specific configuration
- ✅ Independent deployment
- ✅ Flexible policy attachment
- ✅ Team empowerment
- ✅ Scalable architecture

**This is why organizations migrate to Gateway API.**
