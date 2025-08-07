# K3s Cluster Bootstrap System

A modular system for deploying and managing k3s clusters with integrated CI/CD, monitoring, and control panel.

## Features

- 🚀 **Multi-Environment Support**: Deploy to local homelab or Hetzner Cloud
- 📦 **Modular Architecture**: Pick and choose components
- 🔄 **Integrated CI/CD**: Gitea with Actions runners
- 📊 **Full Monitoring Stack**: Prometheus, Grafana, Loki, Alertmanager
- 🎛️ **Control Panel**: Web-based cluster management interface
- 💾 **Flexible Storage**: Support for NAS, Hetzner volumes, and more
- 🔐 **Centralized Auth**: GitHub OAuth SSO across all services
- 🔐 **Backup & DR**: Automated backups with Velero
- 📈 **Auto-scaling**: Dynamic node management based on load
- 🐳 **Container Registry**: Harbor with vulnerability scanning
- 📦 **NPM Registry**: Private package registry with Verdaccio
- 🔑 **Secrets Management**: Sealed Secrets for GitOps workflows

## Quick Start

### Prerequisites
```bash
# Create GitHub OAuth App at https://github.com/settings/applications/new
# Homepage URL: https://your-domain.com
# Callback URL: https://your-domain.com/oauth2/callback

export GITHUB_CLIENT_ID=your-client-id
export GITHUB_CLIENT_SECRET=your-client-secret
export GITHUB_ORG=your-org  # Optional: restrict to org members
```

### Local Deployment
```bash
./bootstrap.sh --environment local --components all --domain your-domain.com
```

### Hetzner Cloud Deployment
```bash
export HETZNER_API_TOKEN=your-token-here
./bootstrap.sh --environment hetzner --components all --domain your-domain.com
```

## Components

| Component | Description | Dependencies |
|-----------|-------------|------------|
| `base` | K3s cluster setup | None |
| `storage` | Storage configuration (NAS/Volumes) | base |
| `secrets` | Sealed Secrets for secure secret management | base |
| `auth` | Centralized GitHub OAuth authentication | base |
| `monitoring` | Prometheus, Grafana, Loki, Alertmanager | base, auth |
| `registry` | Harbor container registry with scanning | base, storage, auth |
| `npm-registry` | Verdaccio private npm registry | base, storage, auth |
| `gitea` | Git server with CI/CD runners | base, storage, auth |
| `k8s-dashboard` | Kubernetes Dashboard | base, auth |
| `control-panel` | Web management interface | base, auth |
| `backup` | Velero backup & disaster recovery | base, storage |

## Architecture

```
┌─────────────────────────────────────────────┐
│      GitHub OAuth SSO (root domain)         │
├─────────────────────────────────────────────┤
│        Control Panel (root domain)          │
├─────────────────────────────────────────────┤
│  git.domain   │  metrics.domain             │
│  (Gitea)      │  (Grafana)                  │
├───────────────┼─────────────────────────────┤
│  npm.domain   │  prometheus.domain          │
│  (Verdaccio)  │  (Prometheus)               │
├───────────────┼─────────────────────────────┤
│registry.domain│  alerts.domain              │
│  (Harbor)     │  (AlertManager)             │
├───────────────┼─────────────────────────────┤
│dashboard.domain│                            │
│ (K8s Dashboard)│                            │
├─────────────────────────────────────────────┤
│         K3s Cluster (Master/Agents)         │
├─────────────────────────────────────────────┤
│    Storage Layer (NAS/Volumes/Local)        │
└─────────────────────────────────────────────┘
```

## Documentation

- [Installation Guide](docs/installation.md)
- [Component Configuration](docs/components.md)
- [Monitoring Stack](docs/monitoring.md)
- [Backup & Disaster Recovery](docs/backup-disaster-recovery.md)
- [Registry & Secrets Management](docs/registry-secrets.md)
- [Hetzner Setup](docs/hetzner.md)
- [Local Homelab Setup](docs/homelab.md)
- [Troubleshooting](docs/troubleshooting.md)

## Requirements

- **Local**: Ubuntu 20.04+ or Debian 11+
- **Hetzner**: CPX11 or higher (2 vCPU, 2GB RAM minimum)
- **Network**: Public IP or proper NAT configuration
- **Domain**: For HTTPS access (optional for local)

## License

MIT