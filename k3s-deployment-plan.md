# K3s Deployment Strategy for GMAC.io Apps

## Current Setup Analysis
- **Server**: Hetzner CPX11 (2 vCPU, 2GB RAM, 40GB SSD) - $4.20/month
- **Current Usage**: Gitea with Actions
- **Available Resources**: ~1.5GB RAM, ~30GB disk after Gitea

## Deployment Options

### Option 1: Same Server (Recommended for Start)
**Pros:**
- No additional cost
- Integrated CI/CD → k3s deployment
- Simple management
- Good for small apps and staging

**Cons:**
- Resource constraints for larger apps
- CI builds compete with app resources
- Single point of failure

### Option 2: Dedicated k3s Server
**Pros:**
- Isolated from CI workloads
- More resources for apps
- Better production stability
- Can scale independently

**Cons:**
- Additional $4.20/month
- More complex networking
- Separate management

## Recommended Approach

### Phase 1: Start with Same Server
1. Install k3s on existing server
2. Deploy staging environments
3. Small production apps (static sites, small APIs)
4. Monitor resource usage

### Phase 2: Scale When Needed
If you experience:
- RAM pressure (>80% usage)
- CPU throttling during builds
- Need for production isolation

Then add dedicated k3s server.

## Resource Allocation Plan

### On Shared Server (2GB RAM Total)
- Gitea: ~400MB
- k3s system: ~300MB
- CI builds: ~500MB (burst)
- **Available for apps: ~800MB**

### Suitable Workloads
- Next.js static exports
- Small Node.js APIs (<200MB)
- Go microservices (<50MB)
- Rust services (<50MB)
- 2-3 staging environments

## Implementation Steps

1. **Install k3s** with resource limits
2. **Configure ingress** with subdomain routing
3. **Set up cert-manager** for automatic HTTPS
4. **Create namespaces**:
   - `staging-*` for feature branches
   - `production` for main branch
5. **Gitea Actions workflows** for deployment
6. **Resource monitoring** with built-in metrics

## Domain Strategy

```
ci.gmac.io          → Gitea
*.k3s.gmac.io       → k3s apps
api.gmac.io         → Production APIs
staging-*.gmac.io   → Staging environments
```

## Example Apps Deployment

### Static Next.js Site
- Build in CI: ~500MB RAM (temporary)
- Nginx pod: ~20MB RAM
- Perfect fit!

### Node.js API
- Build in CI: ~600MB RAM (temporary)
- Runtime pod: ~100-200MB RAM
- 2-3 instances feasible

### Go/Rust Services
- Build in CI: ~800MB RAM (temporary)
- Runtime pod: ~20-50MB RAM
- Many instances possible

## Decision: Start with Same Server

Let's begin with k3s on the same server. This gives us:
- Immediate cost-effective deployment
- Integrated CI/CD pipeline
- Learn resource requirements
- Easy migration path later

We can always add a dedicated server when needed!