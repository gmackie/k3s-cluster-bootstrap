# K3s Bootstrap System - Project Overview

This repository has been transformed into a comprehensive K3s cluster bootstrapping system with multi-node support, automatic scaling, and dynamic node management for both local homelabs and Hetzner Cloud environments.

## Repository Structure

```
.
├── bootstrap.sh                 # Main entry point for cluster deployment
├── lib/
│   └── common.sh               # Shared functions and utilities
├── environments/
│   ├── local/
│   │   └── setup.sh           # Local environment setup
│   └── hetzner/
│       └── setup.sh           # Hetzner Cloud setup with API integration
├── components/
│   ├── base/
│   │   └── install.sh         # K3s base installation (multi-node support)
│   ├── storage/
│   │   └── install.sh         # Storage configuration (local/NFS/Hetzner)
│   ├── monitoring/
│   │   └── install.sh         # Prometheus, Grafana, Alertmanager
│   ├── gitea/
│   │   └── install.sh         # Gitea with CI/CD runners
│   └── control-panel/
│       └── install.sh         # Web-based control panel with scaling
├── scripts/
│   ├── node-add.sh            # Add nodes to cluster
│   ├── node-remove.sh         # Remove nodes with draining
│   ├── cluster-scale.sh       # Automatic scaling logic
│   └── cluster-monitor.sh     # Cluster metrics collection
├── control-panel/              # Control panel application source
├── docs/                       # Documentation
└── .cluster/                   # Runtime configuration (git-ignored)
```

## Key Features

### 1. Multi-Node Cluster Support
- **Dynamic Scaling**: Automatic node addition/removal based on resource usage
- **Multi-Master**: Support for HA control plane configurations
- **Node Management**: Easy node lifecycle management
- **Provider Integration**: Seamless Hetzner API integration for cloud nodes

### 2. Intelligent Scaling
- **Metric-Based**: CPU and memory threshold monitoring
- **Automatic Provisioning**: New nodes created when needed
- **Cost Optimization**: Scale down during low usage
- **Control Panel Integration**: Visual monitoring and manual override

### 3. Modular Architecture
- Each component can be installed independently
- Dependencies are automatically handled
- Easy to extend with new components

### 4. Multi-Environment Support
- **Local**: For homelab deployments
- **Hetzner**: Automated cloud provisioning with API
- **Hybrid**: Mix local and cloud nodes

### 5. Integrated Services
- **Gitea**: Can run on cluster OR managed external VPS
- **Monitoring**: Full Prometheus stack with Grafana
- **Control Panel**: Manages both cluster and external VPS
- **Storage**: Flexible storage options
- **Registry**: Harbor for container images

### 6. Security & Best Practices
- Automatic SSL with cert-manager
- RBAC configuration
- Network policies
- Credential management
- Secure node communication

## Deployment Examples

### Quick Local Setup
```bash
./bootstrap.sh --environment local --components all
```

### Hetzner Production Setup
```bash
export HETZNER_API_TOKEN=your-token
./bootstrap.sh --environment hetzner --components all --domain example.com
```

### Add Monitoring to Existing Cluster
```bash
./bootstrap.sh --components monitoring
```

### Add Worker Node
```bash
# Local node
./scripts/node-add.sh worker worker-1 192.168.1.100

# Hetzner node (automatic provisioning)
PROVIDER=hetzner ./scripts/node-add.sh worker
```

### Scale Cluster Based on Load
```bash
# Check scaling recommendation
./scripts/cluster-scale.sh check

# Auto-scale up if needed
./scripts/cluster-scale.sh scale-up

# Monitor cluster metrics
./scripts/cluster-monitor.sh json all
```

## Component Details

### Base (`base`)
- K3s cluster setup (master/agent nodes)
- NGINX Ingress Controller
- cert-manager for SSL
- Basic RBAC setup

### Storage (`storage`)
- Local path provisioner
- NFS support
- Hetzner volume integration
- Backup configuration

### Monitoring (`monitoring`)
- Prometheus for metrics
- Grafana for visualization
- Alertmanager for notifications
- Pre-configured dashboards
- Custom alerts

### Gitea (`gitea`)
- Git repository hosting
- Integrated CI/CD with Actions
- Docker-in-Docker runners
- Automatic runner registration

### Control Panel (`control-panel`)
- Web-based cluster management
- Deployed at root domain
- Integration with all services
- Real-time monitoring
- Node scaling controls
- Resource usage visualization
- Cost tracking for cloud nodes

## Migration Path

To migrate the existing ci.gmac.io setup:

1. Deploy new cluster with Hetzner:
   ```bash
   export HETZNER_API_TOKEN=your-token
   ./bootstrap.sh --environment hetzner --components all --domain ci.gmac.io
   ```

2. The system will:
   - Provision a new Hetzner server
   - Install K3s with all components
   - Configure DNS (manual step required)
   - Deploy Gitea at ci.gmac.io/git
   - Set up monitoring at ci.gmac.io/grafana
   - Install control panel at ci.gmac.io/

3. Migrate existing Gitea data:
   - Use the gitea-bulk-import.py script
   - Or backup/restore Gitea data

## Next Steps

1. Test the bootstrap system locally
2. Deploy to Hetzner staging environment
3. Migrate production workloads
4. Set up backup automation
5. Configure monitoring alerts
6. Document operational procedures

## Benefits

- **Cost Optimization**: Scale nodes based on actual usage
- **High Availability**: Multi-node clusters with automatic failover
- **Unified Management**: Control panel provides single interface
- **Elastic Scalability**: Automatic scaling based on load
- **Automation**: Minimal manual configuration
- **Flexibility**: Works in multiple environments
- **Resource Efficiency**: Only pay for what you use

## Cluster Scaling Architecture

The system monitors cluster metrics continuously and can:

1. **Scale Up**: When CPU or memory usage exceeds thresholds
   - Automatically provision new Hetzner nodes
   - Add local nodes when specified
   - Distribute workloads across new nodes

2. **Scale Down**: During low usage periods
   - Safely drain nodes before removal
   - Delete cloud resources to save costs
   - Maintain minimum node count

3. **Manual Override**: Via control panel
   - Add/remove specific nodes
   - Adjust scaling thresholds
   - View real-time metrics

The control panel continuously monitors host CPU/memory usage and provides both automatic and manual scaling options, ensuring optimal resource utilization while maintaining application performance.

## Hybrid Infrastructure Support

The system now supports managing both:
- **K3s Cluster**: For cloud-native containerized workloads
- **External VPS**: For services like Gitea that benefit from dedicated resources

This hybrid approach provides:
- **Flexibility**: Run services where they work best
- **SSH Access**: Direct SSH git access for Gitea on dedicated VPS
- **Unified Management**: Single control panel for everything
- **Cost Optimization**: Right-size resources for each service
- **Independence**: Critical services remain available during cluster maintenance