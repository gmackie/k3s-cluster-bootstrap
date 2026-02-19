# GMAC.IO Infrastructure Summary

## 🎯 Overview
A fully operational Kubernetes cluster with comprehensive DevOps tooling, monitoring, and security.

## 🔧 Core Components

### Infrastructure
- **Cluster**: K3s on Hetzner Cloud
  - Master: k3s-master-1 (CPX11 - 2 vCPU, 4GB RAM)
  - Worker: k3s-worker-1 (CPX31 - 4 vCPU, 8GB RAM)
- **Storage**: Longhorn distributed storage
- **Ingress**: NGINX with Let's Encrypt SSL
- **DNS**: All *.gmac.io → 5.78.106.236

### 🚀 Services Deployed

#### Development Tools
- **Gitea** (git.gmac.io) - Git repository hosting
- **ArgoCD** (cd.gmac.io) - GitOps continuous delivery
- **Control Panel** (control.gmac.io) - Service dashboard

#### Container & Package Registries
- **Harbor** (registry.gmac.io) - Docker images & Helm charts
- **Verdaccio** (npm.gmac.io) - Private NPM packages

#### Monitoring & Observability
- **Grafana** (dash.gmac.io, dashboard.gmac.io, metrics.gmac.io)
- **Prometheus** (prometheus.gmac.io)
- **AlertManager** (alertmanager.gmac.io)

#### Management
- **Kubernetes Dashboard** (k3s.gmac.io)
- **Longhorn UI** (longhorn.gmac.io)

## 🔒 Security

### Authentication Layers
1. **Infrastructure Layer**: OAuth2 Proxy
   - Only allows GitHub user: `gmackie`
   - Protects all *.gmac.io domains
   - 24-hour session duration

2. **Application Layer**: Individual app authentication
   - Gitea: GitHub OAuth integration ready
   - Harbor: Local users (admin, ci-build)
   - Verdaccio: htpasswd authentication
   - ArgoCD: Local admin account

### Secrets Management
- Sealed Secrets for GitOps-safe secret storage
- All credentials stored in `.cluster/credentials/`

## 📊 Resource Usage
- **Master Node**: 12% CPU, 81% Memory ⚠️
- **Worker Node**: 3% CPU, 22% Memory ✅

## 🚦 Quick Start Commands

```bash
# NPM Registry
npm login --registry=https://npm.gmac.io
npm publish --registry=https://npm.gmac.io

# Docker Registry
docker login registry.gmac.io
docker push registry.gmac.io/library/myimage:latest

# Git
git clone https://git.gmac.io/username/repo.git

# Kubernetes Access
export KUBECONFIG=~/.kube/config-hetzner
kubectl get nodes
```

## 📝 Maintenance Notes
1. Monitor master node memory usage (currently at 81%)
2. All services require OAuth2 authentication (gmackie only)
3. Verdaccio bypasses OAuth2 for npm CLI compatibility
4. Regular backups recommended for:
   - Gitea repositories
   - Harbor images
   - Verdaccio packages

## 🎉 Status
**All systems operational!** The infrastructure provides a complete DevOps platform with:
- Source control (Gitea)
- CI/CD (ArgoCD)
- Container registry (Harbor)
- Package management (Verdaccio)
- Monitoring (Prometheus/Grafana)
- Security (OAuth2 + app-specific auth)

Last Updated: 2025-09-02