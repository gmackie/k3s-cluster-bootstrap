# Longhorn Component

This component installs Longhorn, a cloud-native distributed block storage system for Kubernetes.

## Features

- **Distributed Block Storage**: Enterprise-grade distributed storage built for Kubernetes
- **Synchronous Replication**: Data protection with configurable replica counts
- **Snapshots & Backups**: Point-in-time snapshots with backup to S3
- **Volume Cloning**: Fast volume cloning for development/testing
- **Storage Tiering**: Automatic data locality optimization
- **Disaster Recovery**: Cross-cluster volume replication
- **Monitoring**: Built-in dashboard and Prometheus metrics
- **CSI Compliant**: Full Kubernetes CSI support

## Architecture

- **Manager**: Orchestrates volume operations
- **Engine**: Handles data I/O operations
- **Replicas**: Store actual data on nodes
- **CSI Driver**: Kubernetes integration
- **UI**: Web-based management interface

## Storage Classes

Three storage classes are created:

### longhorn (Production)
```yaml
numberOfReplicas: "3"
reclaimPolicy: Delete
```
- 3-way replication for high availability
- Deletes volume when PVC is deleted
- Best for production workloads

### longhorn-retain
```yaml
numberOfReplicas: "3"
reclaimPolicy: Retain
```
- Same as above but retains volume data
- Useful for critical data that needs manual cleanup

### longhorn-single-replica
```yaml
numberOfReplicas: "1"
reclaimPolicy: Delete
```
- Single replica for non-critical data
- Better performance, no redundancy
- Good for temporary/cache data

## Usage Examples

### Basic PVC
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

### StatefulSet with Longhorn
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  template:
    spec:
      containers:
      - name: postgres
        image: postgres:14
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: longhorn-retain
      resources:
        requests:
          storage: 50Gi
```

### Volume Snapshot
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot
spec:
  volumeSnapshotClassName: longhorn
  source:
    persistentVolumeClaimName: postgres-data
```

## Backup Configuration

### S3 Backup Target (MinIO)
```bash
# Create backup credentials
kubectl create secret generic backup-secret -n longhorn-system \
  --from-literal=AWS_ACCESS_KEY_ID=admin \
  --from-literal=AWS_SECRET_ACCESS_KEY=your-minio-password \
  --from-literal=AWS_ENDPOINTS=https://s3.yourdomain.com

# Configure backup target in UI or via API
# Backup Target: s3://longhorn-backups@us-east-1/
# Backup Target Credential Secret: backup-secret
```

### External S3 (AWS/GCS/Azure)
```bash
# AWS S3
kubectl create secret generic backup-secret -n longhorn-system \
  --from-literal=AWS_ACCESS_KEY_ID=your-key \
  --from-literal=AWS_SECRET_ACCESS_KEY=your-secret

# Backup Target: s3://your-bucket@us-east-1/longhorn-backups
```

### NFS Backup Target
```bash
# Backup Target: nfs://nfs-server:/backup/longhorn
```

## Recurring Jobs

### Snapshot Schedule
```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: snapshot-hourly
  namespace: longhorn-system
spec:
  cron: "0 * * * *"
  task: "snapshot"
  groups:
  - default
  retain: 24
  concurrency: 2
```

### Backup Schedule
```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: backup-daily
  namespace: longhorn-system
spec:
  cron: "0 2 * * *"
  task: "backup"
  groups:
  - production
  retain: 7
  concurrency: 1
```

## Performance Tuning

### Node Configuration
```bash
# Optimize for performance
echo 'vm.max_map_count = 262144' | sudo tee -a /etc/sysctl.conf
echo 'fs.inotify.max_user_instances = 8192' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Storage Configuration
```yaml
# High-performance settings
apiVersion: longhorn.io/v1beta2
kind: Volume
spec:
  engineSettings:
    replicaAutoBalance: "best-effort"
  dataLocality: "best-effort"
  accessMode: "rwo"
  numberOfReplicas: 2  # Reduce for better performance
```

## Monitoring

### Prometheus Metrics
Longhorn exposes metrics at `http://longhorn-backend:9500/metrics`

Key metrics:
- `longhorn_volume_state`: Volume health status
- `longhorn_volume_capacity_bytes`: Volume capacity
- `longhorn_volume_usage_bytes`: Volume usage
- `longhorn_node_storage_capacity_bytes`: Node storage capacity
- `longhorn_node_storage_usage_bytes`: Node storage usage

### Grafana Dashboard
Import dashboard ID: 13032

### Alerts Example
```yaml
groups:
- name: longhorn
  rules:
  - alert: LonghornVolumeStatusCritical
    expr: longhorn_volume_state{state="detached|faulted"} > 0
    for: 5m
    annotations:
      summary: "Longhorn volume {{ $labels.volume }} is {{ $labels.state }}"
      
  - alert: LonghornNodeStorageLow
    expr: (longhorn_node_storage_usage_bytes / longhorn_node_storage_capacity_bytes) > 0.85
    for: 5m
    annotations:
      summary: "Longhorn node {{ $labels.node }} storage is above 85%"
```

## Disaster Recovery

### Backup Volume
```bash
# Create backup
kubectl -n default annotate pvc my-pvc longhorn.io/backup-volume="true"

# List backups
kubectl -n longhorn-system get backup

# Restore from backup
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restore-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
  dataSource:
    kind: VolumeSnapshot
    name: my-backup
EOF
```

### Cross-Cluster Replication
1. Configure backup target on both clusters
2. Create backup on source cluster
3. Restore from backup on target cluster

## Troubleshooting

### Check Component Status
```bash
# Check all Longhorn pods
kubectl get pods -n longhorn-system

# Check volume status
kubectl get volumes.longhorn.io -n longhorn-system

# Check replicas
kubectl get replicas.longhorn.io -n longhorn-system
```

### Common Issues

1. **Volume Stuck in Attaching**
   ```bash
   # Check node status
   kubectl get nodes.longhorn.io -n longhorn-system
   
   # Force detach
   kubectl -n longhorn-system annotate volume <volume-name> longhorn.io/force-detach="true"
   ```

2. **Replica Rebuilding Slow**
   - Check network bandwidth between nodes
   - Verify disk I/O performance
   - Consider increasing replica rebuild concurrent limit

3. **Cannot Delete PVC**
   ```bash
   # Check finalizers
   kubectl patch pvc <pvc-name> -p '{"metadata":{"finalizers":null}}'
   ```

4. **Node Disk Pressure**
   - Check storage over-provisioning settings
   - Clean up unused snapshots/backups
   - Add more disk space to nodes

### Maintenance Mode

```bash
# Drain node for maintenance
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Disable scheduling on node
kubectl -n longhorn-system annotate nodes.longhorn.io <node-name> \
  node.longhorn.io/scheduling-disabled="true"
```

## Best Practices

1. **Replica Count**
   - Production: 3 replicas
   - Development: 2 replicas
   - Non-critical: 1 replica

2. **Backup Strategy**
   - Daily backups for production
   - Weekly backups with 4-week retention
   - Test restore procedures regularly

3. **Monitoring**
   - Set up alerts for volume health
   - Monitor node storage usage
   - Track backup success rate

4. **Performance**
   - Use local SSDs for best performance
   - Separate Longhorn storage from OS disk
   - Enable data locality for frequently accessed volumes

5. **Upgrades**
   - Always backup before upgrading
   - Test upgrades in development first
   - Follow official upgrade guide

## Migration from Local Path

To migrate existing PVCs from local-path to Longhorn:

```bash
# 1. Create backup of data
kubectl exec -it <pod> -- tar czf /tmp/backup.tar.gz /data

# 2. Copy backup locally
kubectl cp <pod>:/tmp/backup.tar.gz ./backup.tar.gz

# 3. Delete old PVC
kubectl delete pvc <old-pvc>

# 4. Create new PVC with Longhorn
kubectl apply -f new-pvc-longhorn.yaml

# 5. Restore data
kubectl cp ./backup.tar.gz <new-pod>:/tmp/
kubectl exec -it <new-pod> -- tar xzf /tmp/backup.tar.gz -C /
```

## Resource Requirements

- **Manager**: 256Mi memory, 100m CPU
- **Engine**: 128Mi memory per volume
- **Replica**: Depends on volume size
- **Disk Space**: 3x volume size (with 3 replicas)

Minimum recommended per node:
- 4GB RAM
- 20GB free disk space
- 2 CPU cores