# K3s Cluster Bootstrap Deployment Guide

This guide walks you through deploying the K3s cluster bootstrap system from scratch.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Local Deployment](#local-deployment)
4. [Cloud Deployment (Hetzner)](#cloud-deployment-hetzner)
5. [Component Installation](#component-installation)
6. [Post-Installation](#post-installation)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

**Local Deployment:**
- Ubuntu 20.04+ or Debian 11+
- 8GB RAM minimum (16GB recommended)
- 50GB available disk space
- Docker installed
- `kubectl` CLI tool

**Cloud Deployment:**
- Hetzner Cloud account
- CPX21 or higher (4 vCPU, 8GB RAM recommended)
- Domain with DNS management access

### Required Accounts

1. **GitHub OAuth Application**
   - Go to https://github.com/settings/applications/new
   - Application name: `K3s Cluster`
   - Homepage URL: `https://yourdomain.com`
   - Authorization callback URL: `https://yourdomain.com/oauth2/callback`
   - Save Client ID and Client Secret

2. **Domain Name**
   - Purchase domain or use existing
   - Access to DNS management
   - Ability to create A records and CNAME records

3. **Optional Services**
   - SMTP server for email notifications
   - MaxMind account for GeoIP data
   - S3 bucket for external backups

## Environment Setup

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/k3s-cluster-bootstrap.git
cd k3s-cluster-bootstrap
```

### 2. Create Environment File

```bash
cp .env.template .env
```

### 3. Configure Environment Variables

Edit `.env` with your values:

```bash
# Required
DOMAIN=yourdomain.com
GITHUB_CLIENT_ID=your-github-client-id
GITHUB_CLIENT_SECRET=your-github-client-secret

# Optional but recommended
GITHUB_ORG=your-org-name
ADMIN_EMAIL=admin@yourdomain.com

# Email configuration
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_USE_TLS=true
SMTP_FROM=noreply@yourdomain.com
```

### 4. Install Dependencies

```bash
# Install kubectl if not present
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm (optional, for advanced components)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Local Deployment

### 1. Prepare Local Environment

```bash
# Ensure Docker is running
sudo systemctl start docker
sudo systemctl enable docker

# Add current user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Deploy Base Cluster

```bash
# Deploy all components
./bootstrap.sh --environment local --components all --domain localhost

# Or deploy specific components
./bootstrap.sh --environment local \
  --components "base,storage,secrets,auth,monitoring,gitea,drone" \
  --domain localhost
```

### 3. Configure Local DNS

Add to `/etc/hosts`:

```
127.0.0.1 localhost
127.0.0.1 git.localhost
127.0.0.1 registry.localhost
127.0.0.1 metrics.localhost
127.0.0.1 vault.localhost
# Add other subdomains as needed
```

## Cloud Deployment (Hetzner)

### 1. Set Hetzner API Token

```bash
export HETZNER_API_TOKEN=your-hetzner-api-token
```

### 2. Deploy Infrastructure

```bash
./bootstrap.sh --environment hetzner \
  --components all \
  --domain yourdomain.com
```

This will:
- Create a new Hetzner server
- Install K3s
- Configure firewall rules
- Deploy all components

### 3. Configure DNS

Point your domain to the Hetzner server IP:

```
A     @              -> SERVER_IP
A     *              -> SERVER_IP
CNAME git            -> yourdomain.com
CNAME registry       -> yourdomain.com
CNAME metrics        -> yourdomain.com
# etc for all subdomains
```

## Component Installation

### Core Components (Required)

These are always installed:

1. **base** - K3s, ingress controller, cert-manager
2. **storage** - Storage classes and provisioners
3. **secrets** - Sealed secrets controller
4. **auth** - OAuth2 proxy for centralized authentication

### Recommended Components

```bash
# Development environment
./bootstrap.sh --environment local \
  --components "base,storage,secrets,auth,monitoring,gitea,drone,registry,npm-registry" \
  --domain yourdomain.com

# Full collaboration suite
./bootstrap.sh --environment local \
  --components "base,storage,secrets,auth,monitoring,gitea,vaultwarden,nextcloud,matrix" \
  --domain yourdomain.com
```

### Individual Component Installation

```bash
# Install a single component
cd components/sentry
./install.sh

# Uninstall a component
cd components/sentry
./install.sh uninstall
```

### Component Dependencies

Some components require others:

- `drone` requires `gitea`
- `nextcloud` works better with `minio`
- All components (except base) require `auth`

## Post-Installation

### 1. Access Credentials

All credentials are saved in `.cluster/credentials/`:

```bash
# List all credential files
ls -la .cluster/credentials/

# View specific service credentials
cat .cluster/credentials/gitea.conf
cat .cluster/credentials/grafana.conf
```

### 2. Initial Admin Setup

#### Gitea
1. Access https://git.yourdomain.com
2. Login with OAuth (GitHub)
3. Create first repository

#### Grafana
1. Access https://metrics.yourdomain.com
2. Login with OAuth
3. Import dashboards from `monitoring/dashboards/`

#### Nextcloud
1. Access https://files.yourdomain.com
2. Login with admin credentials from `.cluster/credentials/nextcloud.conf`
3. Install recommended apps

### 3. Configure Drone CI

After Gitea is running:

1. Login to Gitea
2. Create OAuth application for Drone
3. Update Drone configuration:

```bash
# Get current credentials
kubectl get secret drone-secrets -n drone -o yaml

# Update with real OAuth credentials
kubectl edit secret drone-secrets -n drone

# Restart Drone
kubectl rollout restart deployment/drone-server -n drone
```

### 4. SSL Certificate Verification

```bash
# Check cert-manager is working
kubectl get certificates --all-namespaces

# Check certificate status
kubectl describe certificate -n gitea gitea-tls
```

## Verification

### 1. Check Component Status

```bash
# Check all pods are running
kubectl get pods --all-namespaces

# Check ingress routes
kubectl get ingress --all-namespaces

# Check persistent volumes
kubectl get pv,pvc --all-namespaces
```

### 2. Test Service Access

```bash
# Test each service endpoint
curl -I https://yourdomain.com
curl -I https://git.yourdomain.com
curl -I https://metrics.yourdomain.com
curl -I https://vault.yourdomain.com
```

### 3. Verify OAuth Flow

1. Open browser in incognito mode
2. Access any protected service
3. Should redirect to GitHub OAuth
4. After authorization, should access service

## Troubleshooting

### Common Issues

#### 1. Pods Not Starting

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check resource availability
kubectl top nodes
kubectl top pods --all-namespaces
```

#### 2. SSL Certificate Issues

```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Force certificate renewal
kubectl delete certificate <cert-name> -n <namespace>

# Check ACME account
kubectl describe clusterissuer letsencrypt-prod
```

#### 3. OAuth Authentication Failures

```bash
# Check OAuth2 proxy logs
kubectl logs -n auth-system deployment/oauth2-proxy

# Verify GitHub OAuth app settings
# Ensure callback URL matches exactly

# Check cookie domain settings
kubectl get configmap oauth2-proxy-config -n auth-system -o yaml
```

#### 4. Storage Issues

```bash
# Check storage classes
kubectl get storageclass

# Check PVC status
kubectl get pvc --all-namespaces

# Check node disk space
kubectl exec -it <node-pod> -- df -h
```

### Debug Commands

```bash
# Get cluster info
kubectl cluster-info

# Check node status
kubectl get nodes -o wide

# View recent events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Check service endpoints
kubectl get endpoints --all-namespaces

# Test DNS resolution
kubectl run -it --rm debug --image=alpine --restart=Never -- nslookup git.yourdomain.com
```

### Recovery Procedures

#### Restore from Backup

```bash
# If using Velero backup
velero restore create --from-backup daily-backup-20231201

# Manual restore
kubectl apply -f backup/namespaces/
kubectl apply -f backup/secrets/
kubectl apply -f backup/deployments/
```

#### Reset Component

```bash
# Completely remove and reinstall component
cd components/gitea
./install.sh uninstall
./install.sh install
```

#### Emergency Access

If OAuth is broken:

```bash
# Temporarily disable auth on a service
kubectl edit ingress <service>-ingress -n <namespace>
# Remove auth annotations

# Create temporary port-forward
kubectl port-forward -n gitea svc/gitea 3000:3000
# Access via http://localhost:3000
```

## Maintenance

### Regular Tasks

1. **Update Components**
   ```bash
   cd components/gitea
   # Edit deployment to use newer image version
   kubectl set image deployment/gitea gitea=gitea/gitea:1.21.0 -n gitea
   ```

2. **Certificate Renewal**
   - Handled automatically by cert-manager
   - Check expiry: `kubectl get certificates --all-namespaces`

3. **Backup Verification**
   ```bash
   # List backups
   velero backup get

   # Verify backup
   velero backup describe <backup-name>
   ```

4. **Resource Monitoring**
   - Access Grafana dashboards
   - Set up alerts for resource usage
   - Review Prometheus metrics

### Security Updates

```bash
# Update K3s
curl -sfL https://get.k3s.io | sh -s - upgrade

# Update all images to latest
kubectl set image deployment --all --all-namespaces *=*:latest

# Apply security patches
kubectl apply -f https://raw.githubusercontent.com/rancher/k3s/master/manifests/metrics-server/metrics-server-deployment.yaml
```

## Next Steps

1. **Configure Monitoring Alerts**
   - Set up Slack/email notifications
   - Define SLOs for services
   - Create custom dashboards

2. **Implement GitOps**
   - Install ArgoCD or Flux
   - Move manifests to Git repository
   - Automate deployments

3. **Enhanced Security**
   - Enable network policies
   - Implement pod security policies
   - Regular security scanning

4. **Performance Optimization**
   - Tune resource requests/limits
   - Enable horizontal pod autoscaling
   - Optimize database configurations

For more detailed information, see:
- [Component Documentation](./components.md)
- [Security Guide](./security.md)
- [Backup and Recovery](./backup-disaster-recovery.md)
- [Monitoring Guide](./monitoring.md)