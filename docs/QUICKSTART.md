# 🚀 K3s Cluster Quick Start Guide

Deploy a production-ready Kubernetes cluster with integrated CI/CD, monitoring, and collaboration tools in minutes!

## 📋 Prerequisites

- **System**: Linux (Ubuntu 20.04+ or Debian 11+) or macOS
- **Resources**: 4GB RAM, 2 CPU cores, 20GB free disk space
- **Network**: Public IP or proper NAT configuration
- **Domain**: Required for HTTPS access (can use a subdomain)

## 🏃‍♂️ Quick Start (5 minutes)

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/gmac-io-ci.git
cd gmac-io-ci
```

### 2. Run the Setup Wizard
```bash
./setup-wizard.sh
```

The wizard will guide you through:
- Domain configuration
- GitHub OAuth setup
- Component selection
- Email configuration (optional)

### 3. Deploy Your Cluster
The wizard automatically runs the deployment after configuration.

## 🎯 What You Get

After deployment, you'll have access to:

| Service | URL | Description |
|---------|-----|-------------|
| Control Panel | `https://yourdomain.com` | Central management dashboard |
| Git Repository | `https://git.yourdomain.com` | Self-hosted Git (Gitea) |
| CI/CD Platform | `https://ci.yourdomain.com` | Drone CI |
| Container Registry | `https://registry.yourdomain.com` | Harbor with vulnerability scanning |
| Monitoring | `https://metrics.yourdomain.com` | Grafana dashboards |
| GitOps | `https://argocd.yourdomain.com` | ArgoCD deployment |
| Notebooks | `https://notebook.yourdomain.com` | JupyterHub |

## 🔐 GitHub OAuth Setup

1. Go to [GitHub OAuth Apps](https://github.com/settings/applications/new)
2. Create a new OAuth App:
   - **Application name**: `K3s Cluster (yourdomain.com)`
   - **Homepage URL**: `https://yourdomain.com`
   - **Authorization callback URL**: `https://yourdomain.com/oauth2/callback`
3. Copy the Client ID and Client Secret for the wizard

## 🛠️ Manual Installation

If you prefer manual configuration:

```bash
# Set required environment variables
export DOMAIN=yourdomain.com
export GITHUB_CLIENT_ID=your-client-id
export GITHUB_CLIENT_SECRET=your-client-secret
export GITHUB_ORG=your-org  # Optional

# Run bootstrap with all components
./bootstrap.sh --environment local --components all --domain $DOMAIN
```

## 📦 Component Profiles

### Essential (Minimum)
```bash
--components "base,storage,secrets,auth,monitoring,gitea,control-panel"
```
- Core infrastructure
- Authentication
- Basic monitoring
- Git repository
- Web dashboard

### Developer (Recommended)
```bash
--components "base,storage,secrets,auth,monitoring,registry,npm-registry,gitea,drone,argocd,sentry,control-panel"
```
- Everything in Essential
- Container & NPM registries
- CI/CD pipeline
- GitOps deployment
- Error tracking

### Full Stack (Everything)
```bash
--components "all"
```
- All available services
- Collaboration tools (Matrix, Mastodon, Mumble)
- JupyterHub for data science
- Advanced identity provider (Authentik)
- Distributed storage (Longhorn)

## 🔍 Pre-flight Checks

Run pre-flight checks before deployment:
```bash
./scripts/preflight-check.sh
```

This validates:
- System requirements
- Network connectivity
- Required software
- Port availability
- Configuration files

## 🌐 DNS Configuration

Before deployment, configure your domain's DNS:

### For Root Domain
```
A    @     your-server-ip
A    *     your-server-ip
```

### For Subdomain
```
A    k3s      your-server-ip
A    *.k3s    your-server-ip
```

## 📝 Post-Deployment

### Access Your Services
1. Visit `https://yourdomain.com`
2. Log in with your GitHub account
3. All services use the same GitHub OAuth

### Default Credentials
- Credentials are saved in `.cluster/credentials/`
- The control panel auto-discovers all deployed services

### Configure Backup
```bash
# Enable automated backups
./scripts/configure-backup.sh
```

## 🚨 Troubleshooting

### Check Cluster Status
```bash
kubectl get nodes
kubectl get pods -A
```

### View Logs
```bash
# Bootstrap logs
tail -f logs/bootstrap-*.log

# Component logs
kubectl logs -n <namespace> <pod-name>
```

### Common Issues

**Port 80/443 in use**
```bash
# Check what's using the ports
sudo lsof -i :80
sudo lsof -i :443
```

**DNS not resolving**
- Ensure your domain's A records point to your server
- Wait 5-10 minutes for DNS propagation

**GitHub OAuth errors**
- Verify callback URL matches exactly
- Check Client ID and Secret are correct
- Ensure your GitHub org membership is public (if using org restriction)

## 🔄 Updates and Maintenance

### Update Components
```bash
# Pull latest changes
git pull

# Re-run specific component
./bootstrap.sh --components "gitea"
```

### Scale Your Cluster
```bash
# Add a worker node
./scripts/node-add.sh --token <join-token> --server <master-ip>
```

## 📚 Next Steps

1. **Import Repositories**: Use the bulk import tool
   ```bash
   python gitea-bulk-import.py
   ```

2. **Configure CI/CD**: Set up Drone CI pipelines in your repositories

3. **Deploy Apps**: Use ArgoCD for GitOps deployments

4. **Monitor**: Check Grafana dashboards at `https://metrics.yourdomain.com`

## 🆘 Getting Help

- **Documentation**: See `/docs` directory
- **Issues**: [GitHub Issues](https://github.com/yourusername/gmac-io-ci/issues)
- **Logs**: Check `logs/` directory

## 🎉 Success!

Your K3s cluster is now running with:
- ✅ Centralized GitHub OAuth authentication
- ✅ Automatic HTTPS with Let's Encrypt
- ✅ Integrated monitoring and alerting
- ✅ Self-hosted Git and CI/CD
- ✅ Container and package registries
- ✅ Web-based management dashboard

Visit your control panel at `https://yourdomain.com` to get started!