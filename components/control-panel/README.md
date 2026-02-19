# GMAC.IO Control Panel

This component deploys the comprehensive GMAC.IO Control Panel - a modern, AI-powered infrastructure management platform.

## Overview

The control panel provides a complete solution for managing your Kubernetes infrastructure, with a modern Next.js frontend and powerful backend services including AI-powered operations.

## Features

### Core Capabilities
- **Modern UI**: Next.js-based dashboard with real-time updates
- **Kubernetes Management**: Full cluster administration and monitoring
- **Service Discovery**: Automatic detection and management of deployed services
- **Monitoring Integration**: Seamless integration with Prometheus, Grafana, and AlertManager
- **GitOps Integration**: Works with Gitea, ArgoCD, and other CI/CD tools

### AI-Powered Operations
- **Incident Prediction**: Machine learning models predict potential incidents before they occur
- **Capacity Planning**: Intelligent forecasting of resource needs
- **Root Cause Analysis**: Automated investigation of incidents
- **Resource Optimization**: Smart recommendations for resource allocation
- **Anomaly Detection**: Multi-method anomaly detection and alerting

## Installation

The control panel is automatically installed when you run the main installation script:

```bash
./install.sh
```

Or install it separately:

```bash
./components/control-panel/install.sh
```

### Configuration Options

Control the installation with environment variables:

```bash
# Basic configuration
export DOMAIN="control.example.com"        # Domain for the control panel
export REGISTRY="ghcr.io/gmac-io"         # Docker registry
export IMAGE_TAG="latest"                  # Image version to deploy
export STORAGE_CLASS="longhorn"           # Storage class for persistent data

# Optional: Disable AI services (for resource-constrained environments)
export ENABLE_AI_SERVICES="false"

./components/control-panel/install.sh
```

## Architecture

The control panel consists of multiple components:

```
┌─────────────────────────────────────────────────────────┐
│                   User Interface                         │
│                  (Next.js Frontend)                      │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                    Backend API                           │
│                  (Python FastAPI)                        │
└─────────────────────────────────────────────────────────┘
                            │
                ┌───────────┴───────────┐
                ▼                       ▼
┌─────────────────────┐     ┌─────────────────────────────┐
│   Kubernetes API    │     │      AI Services            │
└─────────────────────┘     ├─────────────────────────────┤
                           │ • Incident Prediction        │
                           │ • Capacity Planning          │
                           │ • Root Cause Analysis        │
                           │ • Resource Optimization      │
                           │ • Anomaly Detection          │
                           └─────────────────────────────┘
```

## Components

### Frontend (control-panel-frontend)
- **Image**: `ghcr.io/gmac-io/control-panel:latest`
- **Port**: 3000
- **Replicas**: 2
- **Resources**: 256Mi-512Mi RAM, 100m-500m CPU

### Backend (control-panel-backend)
- **Image**: `ghcr.io/gmac-io/control-panel-backend:latest`
- **Port**: 8000
- **Replicas**: 2
- **Resources**: 512Mi-1Gi RAM, 250m-500m CPU

### AI Services (optional)
Each AI service runs as a separate deployment:
- **Images**: `ghcr.io/gmac-io/control-panel-{service}:latest`
- **Port**: 8001
- **Replicas**: 1 each
- **Resources**: 1Gi-2Gi RAM, 500m-1000m CPU per service

## Resource Requirements

### Minimum (without AI services)
- **CPU**: 700m (350m per replica)
- **Memory**: 1.5Gi (768Mi per replica)
- **Storage**: 10Gi for persistent data

### Recommended (with AI services)
- **CPU**: 4 cores
- **Memory**: 8Gi
- **Storage**: 10Gi for persistent data

## Access

After installation, access the control panel at:

```
https://<your-domain>
```

Default endpoints:
- Frontend: `https://<your-domain>/`
- Backend API: `https://<your-domain>/api`
- Health Check: `https://<your-domain>/api/health`

## Integration with Other Components

The control panel automatically detects and integrates with:

- **Monitoring**: Prometheus, Grafana, AlertManager
- **Git**: Gitea
- **CI/CD**: Drone, ArgoCD
- **Registry**: Harbor, Verdaccio
- **Storage**: Longhorn, MinIO
- **Databases**: PostgreSQL deployments
- **Security**: Authentik, OAuth2 Proxy

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n control-panel
```

### View Logs
```bash
# Frontend logs
kubectl logs -f deployment/control-panel-frontend -n control-panel

# Backend logs
kubectl logs -f deployment/control-panel-backend -n control-panel

# AI service logs (if enabled)
kubectl logs -f deployment/control-panel-incident-prediction -n control-panel
```

### Common Issues

1. **Pods not starting**: Check resource availability
   ```bash
   kubectl describe pod -n control-panel <pod-name>
   ```

2. **AI services failing**: Ensure sufficient memory (1Gi+ per service)
   ```bash
   # Disable AI services if resources are limited
   export ENABLE_AI_SERVICES=false
   ./components/control-panel/install.sh
   ```

3. **Cannot access UI**: Check ingress configuration
   ```bash
   kubectl get ingress -n control-panel
   kubectl describe ingress control-panel -n control-panel
   ```

## Development

The control panel source code is maintained at:
https://github.com/gmac-io/control-panel

### Building Custom Images

```bash
# Clone the repository
git clone https://github.com/gmac-io/control-panel
cd control-panel

# Build and push images
docker build --target frontend -t your-registry/control-panel:custom .
docker build --target backend -t your-registry/control-panel-backend:custom .

# Deploy with custom images
export REGISTRY="your-registry"
export IMAGE_TAG="custom"
./install.sh
```

## Updates

The control panel follows semantic versioning. To update:

```bash
# Update to latest version
export IMAGE_TAG="latest"
./components/control-panel/install.sh

# Or specify a version
export IMAGE_TAG="v1.2.3"
./components/control-panel/install.sh
```

## Security

- All components run with minimal privileges
- Network policies restrict inter-pod communication
- RBAC is configured for Kubernetes API access
- Images are regularly scanned for vulnerabilities
- TLS is enforced for all external communication

## Support

- GitHub Issues: https://github.com/gmac-io/control-panel/issues
- Documentation: https://docs.gmac.io/control-panel
- Community: https://discord.gg/gmac-io