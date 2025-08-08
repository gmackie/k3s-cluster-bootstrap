# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
This is a comprehensive K3s cluster bootstrapping system that evolved from a simple Gitea CI/CD setup. It provides a self-hosted, cost-effective alternative to GitHub Actions and Vercel with full control over the infrastructure.

**Note**: The codebase has been cleaned up to focus on the modular K3s bootstrap system. All legacy Gitea-only scripts and configurations have been removed in favor of the component-based architecture.

## Architecture
- **Multi-environment support**: Local homelab or Hetzner Cloud deployment
- **Modular components**: Base K3s, Auth, Gitea, Registry, NPM Registry, Monitoring, Storage, Ingress, Auto-scaling
- **Hybrid infrastructure**: Supports both K3s workloads and dedicated VPS instances
- **GitHub Actions compatible**: All workflows work with standard GitHub Actions syntax
- **Private package management**: Verdaccio npm registry integrated with centralized OAuth for hosting internal API libraries
- **Centralized authentication**: GitHub OAuth at root domain with SSO across all services

## Essential Commands

### Initial Setup
```bash
# Set up Python environment and initialize project
./setup.sh

# Set up GitHub OAuth (required for auth component)
export GITHUB_CLIENT_ID="your-client-id"
export GITHUB_CLIENT_SECRET="your-client-secret"
export GITHUB_ORG="your-org"  # Optional: restrict to org members

# Deploy full K3s cluster with all components
./bootstrap.sh --environment local --components all --domain example.com
./bootstrap.sh --environment hetzner --components all --domain example.com
```

### Repository Migration
```bash
# Interactive GitHub repository import
python gitea-bulk-import.py

# Automated bulk import
./quick-bulk-import.sh
```

### Cluster Management
```bash
# Add/remove nodes
./scripts/node-add.sh worker worker-1 192.168.1.100
./scripts/node-remove.sh worker-1

# Monitor cluster
./scripts/cluster-monitor.sh json all
./scripts/cluster-scale.sh check
```

### Remote Server Management
```bash
# Check Gitea status
ssh root@5.78.92.8 "docker ps"

# View Gitea logs
ssh root@5.78.92.8 "docker logs gitea"

# Restart services
ssh root@5.78.92.8 "cd /opt/gitea && docker-compose restart"
```

### Development
```bash
# Run linting and checks
npm run lint
npm run typecheck
npm run build
```

### NPM Registry Management
```bash
# Configure npm to use private registry
npm config set registry https://npm.${DOMAIN}
npm config set @gmac:registry https://npm.${DOMAIN}

# Login via browser to get token
# Visit https://npm.${DOMAIN} and copy token from profile

# Set token in npm config
npm config set //npm.${DOMAIN}/:_authToken <your-token>

# Publish private packages
npm publish --registry https://npm.${DOMAIN}
```

## Key Files and Directories

### Core Scripts
- `bootstrap.sh`: Main entry point for cluster deployment
- `lib/common.sh`: Shared utilities and logging functions
- `gitea-bulk-import.py`: GitHub repository migration tool
- `quick-bulk-import.sh`: Automated bulk import script
- `setup.sh`: Development environment initialization

### Component Modules
- `components/base/`: K3s base installation
- `components/gitea/`: Gitea with CI runners
- `components/monitoring/`: Prometheus/Grafana stack
- `components/storage/`: NFS/Hetzner volume configuration
- `components/registry/`: Container registry with UI
- `components/npm-registry/`: Private npm registry (Verdaccio) for API libraries
- `components/ingress/`: Nginx ingress controller
- `components/autoscaling/`: Resource-based scaling

### Environment Configurations
- `environments/local/`: Homelab deployment settings
- `environments/hetzner/`: Hetzner Cloud API integration

### Workflow Templates
- `example-workflows/`: GitHub Actions compatible workflows for different project types
- `workflows/`: Production deployment pipelines

### Documentation
- `README.md`: K3s bootstrap system overview and quick start
- `PROJECT_OVERVIEW.md`: Detailed repository structure and features
- `PROJECT_CONTEXT.md`: Historical context and deployment status
- `ci-architecture.md`: Self-hosted CI/CD architecture overview
- `docs/`: Additional documentation for specific features

## Development Workflow

1. **Making Changes**: Always check existing patterns in similar files
2. **Testing**: Use the local environment first before deploying to Hetzner
3. **Component Development**: Each component is self-contained in its directory
4. **Script Standards**: All scripts use the common.sh library for consistency

## Important Considerations

- **Cost Optimization**: Keep the lightweight nature while ensuring reliability
- **GitHub Actions Compatibility**: Maintain compatibility with standard workflows
- **Modular Design**: Components can be installed/removed independently
- **Error Handling**: All scripts include comprehensive error checking
- **Logging**: Use the provided logging functions from lib/common.sh

## Current Infrastructure
- **Primary Server**: ci.gmac.io (5.78.92.8) on Hetzner CPX11
- **Platform**: Gitea with Actions runners
- **Supported Apps**: Next.js, Vite, Go, Rust applications
- **Protocols**: HTTP/HTTPS, WS/WSS, MQTT

## Service URLs (with centralized auth)
When deployed with a domain, services are available at:
- **Control Panel**: `https://<domain>` (root domain)
- **OAuth2 Auth**: `https://<domain>/oauth2/*`
- **Grafana**: `https://metrics.<domain>`
- **Prometheus**: `https://prometheus.<domain>`
- **AlertManager**: `https://alerts.<domain>`
- **Gitea**: `https://git.<domain>`
- **Harbor Registry**: `https://registry.<domain>`
- **NPM Registry**: `https://npm.<domain>`
- **K8s Dashboard**: `https://dashboard.<domain>`
- **Matrix/Element**: `https://matrix.<domain>` / `https://chat.<domain>`
- **Mastodon**: `https://social.<domain>`
- **Mumble Web**: `https://voice.<domain>` (server: voice.<domain>:64738)
- **JupyterHub**: `https://notebook.<domain>`

All services use GitHub OAuth for authentication through the centralized auth component.

## Testing Approach
The project includes comprehensive testing scripts:
- Component installation verification
- Node management testing
- Scaling behavior validation
- Monitoring stack checks

When developing new features, ensure they integrate with the existing modular architecture and maintain backward compatibility with GitHub Actions workflows.