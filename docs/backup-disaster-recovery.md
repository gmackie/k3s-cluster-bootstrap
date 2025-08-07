# Backup and Disaster Recovery Guide

## Overview

The K3s cluster includes a comprehensive backup and disaster recovery system using Velero for application backups and custom scripts for etcd backups.

## Components

### 1. Velero
- **Purpose**: Backup and restore Kubernetes resources and persistent volumes
- **Features**:
  - Scheduled backups
  - On-demand backups
  - Selective restoration
  - Multi-cloud support

### 2. etcd Backup
- **Purpose**: Backup cluster state database
- **Schedule**: Daily at 1 AM
- **Retention**: 7 days

### 3. Storage Providers
- **Local**: MinIO S3-compatible storage
- **AWS S3**: Cloud backup storage
- **Azure Blob**: Azure backup storage

## Backup Schedules

| Schedule Name | Frequency | Time | Retention | Scope |
|--------------|-----------|------|-----------|--------|
| daily-backup | Daily | 2 AM | 30 days | All namespaces |
| weekly-full-backup | Weekly | Sunday 3 AM | 90 days | Full cluster |
| critical-apps-backup | 6 hours | Every 6h | 7 days | Critical apps |
| etcd-backup | Daily | 1 AM | 7 days | etcd data |

## Backup Operations

### Manual Backup

```bash
# Create on-demand backup
velero backup create manual-backup-$(date +%Y%m%d-%H%M%S)

# Backup specific namespace
velero backup create gitea-backup --include-namespaces gitea

# Backup with custom TTL
velero backup create temp-backup --ttl 24h
```

### List Backups

```bash
# List all backups
velero backup get

# Describe specific backup
velero backup describe daily-backup-20240115

# View backup logs
velero backup logs daily-backup-20240115
```

### Monitor Backup Health

```bash
# Get backup system status
./scripts/backup-monitor.sh summary

# Detailed backup information
./scripts/backup-monitor.sh detailed

# JSON output for automation
./scripts/backup-monitor.sh json
```

## Disaster Recovery Procedures

### Scenario 1: Application Failure

**When to use**: Single application or namespace is corrupted

```bash
# 1. List available backups
./scripts/disaster-recovery.sh list

# 2. Restore specific namespace
velero restore create --from-backup daily-backup-20240115 \
  --include-namespaces gitea

# 3. Verify restoration
kubectl get all -n gitea
```

### Scenario 2: Node Failure

**When to use**: One or more nodes have failed

```bash
# 1. Remove failed node
./scripts/node-remove.sh <failed-node> true

# 2. Add replacement node
./scripts/node-add.sh worker

# 3. Wait for workloads to reschedule
kubectl get pods --all-namespaces -o wide
```

### Scenario 3: Complete Cluster Failure

**When to use**: Entire cluster is lost

```bash
# 1. Provision new cluster
./bootstrap.sh --environment hetzner --components base

# 2. Install Velero with same configuration
./bootstrap.sh --components backup

# 3. List remote backups
velero backup get

# 4. Restore full cluster
./scripts/disaster-recovery.sh restore weekly-full-backup-20240114

# 5. Restore etcd if needed
# Copy etcd snapshot to master node and run:
etcdctl snapshot restore /path/to/snapshot.db \
  --data-dir=/var/lib/etcd-restore

# 6. Verify cluster health
kubectl get nodes
kubectl get pods --all-namespaces
```

### Scenario 4: Data Corruption

**When to use**: Data is corrupted but cluster is operational

```bash
# 1. Identify corrupted resources
kubectl get all --all-namespaces | grep -E "Error|CrashLoop"

# 2. Delete corrupted resources
kubectl delete deployment/corrupted-app -n production

# 3. Restore from backup
velero restore create --from-backup daily-backup-20240115 \
  --include-resources deployments,services,configmaps \
  --include-namespaces production

# 4. Verify data integrity
kubectl exec -n production deployment/app -- /health-check.sh
```

## Backup Testing

### Automated DR Testing

```bash
# Run disaster recovery simulation
./scripts/disaster-recovery.sh simulate

# This will:
# 1. Create test namespace with sample app
# 2. Create backup
# 3. Delete namespace (simulate disaster)
# 4. Restore from backup
# 5. Verify restoration
```

### Manual Testing Procedure

1. **Create Test Data**
   ```bash
   kubectl create namespace dr-test
   kubectl create deployment nginx --image=nginx -n dr-test
   kubectl create configmap test-data --from-literal=data="test" -n dr-test
   ```

2. **Backup Test Data**
   ```bash
   velero backup create dr-test-backup --include-namespaces dr-test
   ```

3. **Simulate Failure**
   ```bash
   kubectl delete namespace dr-test
   ```

4. **Restore and Verify**
   ```bash
   velero restore create --from-backup dr-test-backup
   kubectl get all -n dr-test
   ```

## Recovery Time Objectives (RTO)

| Scenario | Target RTO | Typical RTO | Notes |
|----------|------------|-------------|--------|
| App restore | 15 min | 5-10 min | Single namespace |
| Node replacement | 30 min | 15-20 min | Automated provisioning |
| Full cluster | 2 hours | 1 hour | Complete restoration |
| etcd restore | 30 min | 15 min | Cluster state only |

## Recovery Point Objectives (RPO)

| Data Type | Maximum Data Loss | Backup Frequency |
|-----------|-------------------|------------------|
| Critical apps | 6 hours | Every 6 hours |
| Standard apps | 24 hours | Daily |
| Cluster config | 24 hours | Daily |
| etcd state | 24 hours | Daily |

## Backup Storage Management

### Storage Locations

```bash
# List backup locations
velero backup-location get

# Create new backup location
velero backup-location create s3-backup \
  --provider aws \
  --bucket my-backup-bucket \
  --config region=us-east-1
```

### Storage Optimization

```bash
# Clean old backups
velero backup delete --confirm --all --selector 'velero.io/ttl-expired=true'

# Export backup for archival
./scripts/disaster-recovery.sh export daily-backup-20240115 /mnt/archive/
```

## Monitoring and Alerts

### Backup Failure Alerts

Alert rules are configured for:
- Backup job failures
- Missed backup schedules
- Storage capacity warnings
- Velero component health

### Backup Metrics

Available metrics:
- `backup_total_count` - Total backups
- `backup_successful_count` - Successful backups
- `backup_failed_count` - Failed backups
- `backup_storage_bytes` - Storage usage
- `backup_last_timestamp` - Last backup time

## Best Practices

1. **Regular Testing**
   - Run DR simulations monthly
   - Test restoration procedures quarterly
   - Document test results

2. **Backup Verification**
   - Verify backups after creation
   - Check backup logs for warnings
   - Monitor backup sizes for anomalies

3. **Documentation**
   - Keep runbooks updated
   - Document application-specific procedures
   - Maintain contact lists

4. **Security**
   - Encrypt backups at rest
   - Use separate credentials for backup storage
   - Regularly rotate access keys

5. **Monitoring**
   - Set up alerts for backup failures
   - Monitor storage capacity
   - Track backup/restore metrics

## Troubleshooting

### Backup Failures

```bash
# Check Velero logs
kubectl logs -n backup deployment/velero

# Check backup status
velero backup describe <backup-name> --details

# View backup logs
velero backup logs <backup-name>
```

### Restore Issues

```bash
# Check restore status
velero restore describe <restore-name>

# View restore logs
velero restore logs <restore-name>

# List partially failed items
velero restore describe <restore-name> --details | grep -i error
```

### Storage Problems

```bash
# Test storage connectivity
kubectl exec -n backup deployment/velero -- velero backup-location get

# Check storage credentials
kubectl get secret -n backup cloud-credentials -o yaml
```

## Disaster Recovery Checklist

- [ ] Verify latest backup is successful
- [ ] Confirm backup storage is accessible
- [ ] Review application dependencies
- [ ] Notify stakeholders
- [ ] Execute restoration procedure
- [ ] Verify data integrity
- [ ] Test application functionality
- [ ] Document incident and lessons learned
- [ ] Update procedures if needed
- [ ] Schedule post-mortem meeting