# Hybrid Infrastructure Management

The control panel can manage both the K3s cluster and external VPS instances, providing a unified interface for your entire infrastructure.

## Overview

This approach gives you the best of both worlds:
- **K3s Cluster**: For containerized workloads, auto-scaling, and cloud-native applications
- **Dedicated VPS**: For services that need dedicated resources, SSH access, or legacy applications

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Control Panel                         │
│                 (Manages Everything)                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────────┐      ┌──────────────────┐    │
│  │    K3s Cluster      │      │   External VPS    │    │
│  │                     │      │                   │    │
│  │ • Control Panel     │      │ • Gitea           │    │
│  │ • Harbor Registry   │      │ • PostgreSQL      │    │
│  │ • Monitoring Stack  │      │ • Legacy Apps     │    │
│  │ • Microservices     │      │                   │    │
│  │ • Auto-scaling      │      │                   │    │
│  └─────────────────────┘      └──────────────────┘    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Why Keep Gitea on Separate VPS?

1. **SSH Git Access**: Direct SSH access on port 22 without complexity
2. **Dedicated Resources**: Git operations don't compete with cluster workloads
3. **Independence**: Git remains available even during cluster maintenance
4. **Existing Setup**: If already working well, no need to migrate
5. **Backup Simplicity**: Easier to backup/restore a dedicated service

## VPS Management Features

### Adding Existing VPS to Management

```bash
# Add your existing Gitea VPS
./scripts/vps-manage.sh add gitea \
  --ip 5.78.92.8 \
  --domain ci.gmac.io \
  --services gitea,postgres,nginx \
  --provider hetzner

# The control panel will now:
# - Monitor VPS health
# - Track resource usage
# - Provide SSH access
# - Manage backups
# - Show unified dashboard
```

### VPS Operations

```bash
# Check VPS status
./scripts/vps-manage.sh status gitea

# SSH into VPS
./scripts/vps-manage.sh ssh gitea

# Backup VPS data
./scripts/vps-manage.sh backup gitea

# Setup monitoring
./scripts/vps-manage.sh monitor gitea
```

### Control Panel Integration

The control panel provides:
- **Unified Dashboard**: See both cluster and VPS status
- **Resource Monitoring**: CPU, memory, disk usage across all infrastructure
- **Health Checks**: Automatic monitoring of services
- **SSH Terminal**: Web-based SSH access to VPS instances
- **Backup Management**: Scheduled backups for both cluster and VPS

## Monitoring External VPS

### Automatic Monitoring Setup

When you add a VPS, the system can automatically:
1. Install Prometheus node_exporter
2. Configure firewall rules
3. Add as Prometheus target
4. Create Grafana dashboards

```bash
# Setup monitoring (prompted during add, or run manually)
./scripts/vps-manage.sh monitor gitea
```

### Metrics Available

- System metrics (CPU, memory, disk, network)
- Service health status
- SSH connectivity
- HTTP/HTTPS endpoint monitoring
- Custom application metrics

## Hybrid Deployment Patterns

### Pattern 1: Core Services on VPS
- **VPS**: Gitea, databases, file storage
- **Cluster**: Applications, APIs, microservices

### Pattern 2: Production/Development Split
- **VPS**: Production services requiring stability
- **Cluster**: Development, staging, experimental services

### Pattern 3: Geographic Distribution
- **VPS**: Services in specific regions
- **Cluster**: Global services with auto-scaling

## Cost Optimization

Running hybrid infrastructure can be cost-effective:

| Service | Best Deployed On | Reason |
|---------|-----------------|---------|
| Gitea | Dedicated VPS | SSH access, stable resource needs |
| Databases | Dedicated VPS or Cluster with operators | Depends on size and criticality |
| Web Apps | K3s Cluster | Auto-scaling, load balancing |
| CI/CD Runners | K3s Cluster | Dynamic scaling based on jobs |
| Monitoring | K3s Cluster | Integrated with all services |
| File Storage | Dedicated VPS | Direct access, simple backups |

## Security Considerations

### Network Security
- VPS and cluster can be in same private network (Hetzner vSwitch)
- Firewall rules limit access between components
- VPN connection for management access

### Access Control
- Single control panel for all infrastructure
- RBAC for different team members
- Audit logging across all systems

## Backup Strategy

### Unified Backups
```bash
# Backup everything from control panel
# - Cluster: Uses Velero
# - VPS: Uses custom scripts

# Schedule automated backups
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vps-backup
  namespace: control-panel
spec:
  schedule: "0 3 * * *"  # Daily at 3 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: control-panel:latest
            command: ["/app/scripts/vps-manage.sh", "backup", "all"]
EOF
```

### Disaster Recovery
- Cluster: Restore with Velero
- VPS: Restore from backup + Terraform/Ansible
- Both managed from control panel

## Scaling Strategies

### When to Add VPS
- Service needs dedicated resources
- Requires specific OS/kernel features
- Needs direct SSH access
- Geographic requirements

### When to Scale Cluster
- Microservices architecture
- Need auto-scaling
- Container-based workloads
- Cost optimization (scale to zero)

## Best Practices

1. **Inventory Management**
   - Keep VPS inventory updated
   - Document service dependencies
   - Track resource allocation

2. **Monitoring**
   - Unified dashboards for all infrastructure
   - Alert routing based on service type
   - Capacity planning across both platforms

3. **Security**
   - Regular updates on both VPS and cluster
   - Centralized secret management
   - Network isolation where needed

4. **Cost Tracking**
   - Tag resources appropriately
   - Monitor usage patterns
   - Right-size VPS instances

## Example: Complete Setup

```bash
# 1. Deploy K3s cluster with control panel
./bootstrap.sh --environment hetzner --components all

# 2. Add existing Gitea VPS
./scripts/vps-manage.sh add gitea --ip 5.78.92.8 --domain ci.gmac.io

# 3. Setup monitoring for VPS
./scripts/vps-manage.sh monitor gitea

# 4. Configure backups
kubectl apply -f templates/backup-schedules.yaml

# 5. Access control panel
# https://control.yourdomain.com
# - View unified dashboard
# - Manage both cluster and VPS
# - Monitor all resources
```

## Troubleshooting

### VPS Connection Issues
```bash
# Check SSH connectivity
ssh root@vps-ip

# Update inventory
./scripts/vps-manage.sh add gitea --ip new-ip

# Check firewall rules
./scripts/vps-manage.sh status gitea
```

### Monitoring Issues
```bash
# Check node_exporter on VPS
ssh root@vps-ip systemctl status node_exporter

# Verify Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090
# Visit http://localhost:9090/targets
```

### Control Panel Issues
```bash
# Check control panel logs
kubectl logs -n control-panel deployment/control-panel

# Verify VPS inventory
kubectl get configmap -n control-panel vps-inventory -o yaml
```