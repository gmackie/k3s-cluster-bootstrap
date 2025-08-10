# K3s Cluster Bootstrap System

A modular, production-ready Kubernetes cluster deployment system built on K3s with integrated CI/CD, monitoring, and collaboration tools.

## Features

- 🚀 **Multi-Environment Support**: Deploy to local homelab or Hetzner Cloud
- 📦 **Modular Architecture**: Pick and choose components
- 🔄 **Integrated CI/CD**: Gitea with Drone CI platform
- 📊 **Full Monitoring Stack**: Prometheus, Grafana, Loki, Alertmanager
- 🎛️ **Control Panel**: Web-based cluster management interface
- 💾 **Flexible Storage**: Local-path, NAS, S3-compatible (MinIO)
- 🔐 **Centralized Auth**: GitHub OAuth SSO across all services
- 🆔 **Identity Provider**: Authentik for OAuth2, SAML, LDAP support
- 🔐 **Backup & DR**: Automated backups with Velero
- 🐳 **Container Registry**: Harbor with vulnerability scanning
- 📦 **NPM Registry**: Private package registry with Verdaccio
- 🔑 **Secrets Management**: Sealed Secrets for GitOps workflows
- 🔒 **Password Manager**: Vaultwarden (Bitwarden compatible)
- 📁 **File Sharing**: Nextcloud with S3 backend support
- 💬 **Team Communication**: Matrix chat, Mastodon, Mumble voice
- 📓 **Data Science**: JupyterHub multi-user notebooks

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
| `base` | K3s cluster setup, ingress, cert-manager | None |
| `storage` | Storage classes and provisioners | base |
| `longhorn` | Distributed block storage system | base, storage |
| `secrets` | Sealed Secrets for secure secret management | base |
| `auth` | Centralized GitHub OAuth authentication | base |
| `authentik` | Advanced identity provider (OAuth2, SAML, LDAP) | base, storage |
| `monitoring` | Prometheus, Grafana, Loki, Alertmanager | base, auth |
| `registry` | Harbor container registry with scanning | base, storage, auth |
| `npm-registry` | Verdaccio private npm registry | base, storage, auth |
| `gitea` | Git server with webhooks | base, storage, auth |
| `drone` | Container-native CI/CD platform | base, storage, auth, gitea |
| `k8s-dashboard` | Kubernetes Dashboard | base, auth |
| `vaultwarden` | Password manager (Bitwarden compatible) | base, storage, auth |
| `minio` | S3-compatible object storage | base, storage |
| `nextcloud` | File sync and collaboration | base, storage, auth, minio (optional) |
| `sentry` | Application error tracking and monitoring | base, storage, auth |
| `plausible` | Privacy-focused web analytics | base, storage, auth |
| `matrix` | Matrix chat server with Element web client | base, storage, auth |
| `mastodon` | Federated social network | base, storage, auth |
| `mumble` | Voice chat server with web interface | base, auth |
| `jupyterhub` | Multi-user Jupyter notebook server | base, storage, auth |
| `control-panel` | Web management interface | base, auth |
| `backup` | Velero backup & disaster recovery | base, storage |

## Architecture

```
┌─────────────────────────────────────────────┐
│      GitHub OAuth SSO (root domain)         │
├─────────────────────────────────────────────┤
│        Control Panel (root domain)          │
├─────────────────────────────────────────────┤
│  git.domain   │  ci.domain                  │
│  (Gitea)      │  (Drone CI)                 │
├───────────────┼─────────────────────────────┤
│  npm.domain   │  metrics.domain             │
│  (Verdaccio)  │  (Grafana)                  │
├───────────────┼─────────────────────────────┤
│registry.domain│  vault.domain               │
│  (Harbor)     │  (Vaultwarden)              │
├───────────────┼─────────────────────────────┤
│  s3.domain    │  files.domain               │
│  (MinIO)      │  (Nextcloud)                │
├───────────────┼─────────────────────────────┤
│sentry.domain  │  analytics.domain           │
│  (Sentry)     │  (Plausible)                │
├───────────────┼─────────────────────────────┤
│dashboard.domain│  notebook.domain           │
│ (K8s Dashboard)│  (JupyterHub)              │
├───────────────┼─────────────────────────────┤
│matrix.domain  │  chat.domain                │
│ (Matrix Server)│  (Element Web)              │
├───────────────┼─────────────────────────────┤
│social.domain  │  voice.domain               │
│ (Mastodon)     │  (Mumble)                   │
├─────────────────────────────────────────────┤
│         K3s Cluster (Master/Agents)         │
├─────────────────────────────────────────────┤
│    Storage Layer (Local/S3/Volumes)         │
└─────────────────────────────────────────────┘
```

## Collaboration Services

The cluster includes several collaboration and communication services:

### Matrix Chat
- **Server**: Synapse at `matrix.<domain>`
- **Web Client**: Element at `chat.<domain>`
- **Features**: End-to-end encryption, federation, voice/video calls
- **Federation**: Enabled for communication with other Matrix servers

### Mastodon Social
- **URL**: `social.<domain>`
- **Features**: Federated social network, ActivityPub support
- **Storage**: Media uploads, user content

### Mumble Voice
- **Web**: `voice.<domain>`
- **Server**: `voice.<domain>:64738` (TCP/UDP)
- **Features**: Low-latency voice chat, channel management
- **Access**: Download Mumble client to connect

### JupyterHub Notebooks
- **URL**: `notebook.<domain>`
- **Features**: Multi-user Jupyter notebooks
- **Environments**: Python, R, TensorFlow, Data Science
- **Storage**: 10GB per user

## Documentation

- [Deployment Guide](docs/deployment-guide.md) - Complete step-by-step deployment instructions
- [Monitoring Stack](docs/monitoring.md)
- [Backup & Disaster Recovery](docs/backup-disaster-recovery.md)
- [Registry & Secrets Management](docs/registry-secrets.md)
- [Hybrid Infrastructure](docs/hybrid-infrastructure.md)

## Requirements

- **Local**: Ubuntu 20.04+ or Debian 11+
- **Hetzner**: CPX11 or higher (2 vCPU, 2GB RAM minimum)
- **Network**: Public IP or proper NAT configuration
- **Domain**: For HTTPS access (optional for local)

## License

MIT