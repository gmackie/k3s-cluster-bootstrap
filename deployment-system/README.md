# Gitea → Kubernetes Auto-Deployment System

This directory contains the complete auto-deployment system for deploying any Gitea repository to your Kubernetes cluster.

## Quick Install

```bash
cd /Volumes/dev/gmac-io-ci/deployment-system
./deployment-system-setup.sh
```

## Quick Deploy

After installation:
```bash
deploy-app <repository-name> [custom-domain] [port]
```

## Files in this directory:

- `deploy-app.sh` - Main deployment script
- `easy-deploy.sh` - Interactive deployment wizard
- `deployment-system-setup.sh` - System installer
- `test-deployment.sh` - Test the deployment system
- `.github-workflow-template.yml` - CI/CD workflow template
- `generic-app-chart/` - Helm chart for complex deployments
- `auto-deploy-appset.yaml` - ArgoCD ApplicationSet config
- `deployment-ui/` - Web UI for managing deployments
- `auto-deployment-guide.md` - Detailed user guide
- `DEPLOYMENT-SYSTEM.md` - Complete system documentation

## Example Usage

```bash
# Interactive mode
deploy-app

# Deploy with defaults (repo-name.gmac.io)
deploy-app my-awesome-app

# Deploy with custom domain
deploy-app my-app app.example.com 8080
```

See `DEPLOYMENT-SYSTEM.md` for complete documentation.