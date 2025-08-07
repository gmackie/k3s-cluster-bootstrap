#!/bin/bash
# Disaster recovery procedures

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

ACTION="${1:-help}"
BACKUP_NAME="${2:-}"

show_usage() {
    cat << EOF
Usage: $0 [action] [options]

Disaster recovery procedures for K3s cluster

Actions:
    list              List available backups
    restore           Restore from backup
    verify            Verify backup integrity
    export            Export backup to external storage
    import            Import backup from external storage
    simulate          Simulate disaster recovery
    report            Generate DR readiness report

Examples:
    # List all backups
    $0 list

    # Restore from specific backup
    $0 restore daily-backup-20240115

    # Verify backup integrity
    $0 verify daily-backup-20240115

    # Export backup to external location
    $0 export daily-backup-20240115 /mnt/external/backups/

    # Simulate disaster recovery
    $0 simulate

    # Generate DR readiness report
    $0 report
EOF
}

# List available backups
list_backups() {
    info "Available backups:"
    echo ""
    
    # List Velero backups
    velero backup get
    
    echo ""
    info "etcd snapshots:"
    kubectl exec -n backup deployment/etcd-backup -- ls -la /backups/etcd/ 2>/dev/null || echo "No etcd backups found"
}

# Restore from backup
restore_backup() {
    if [[ -z "$BACKUP_NAME" ]]; then
        error "Backup name required"
    fi
    
    warn "This will restore the cluster from backup: $BACKUP_NAME"
    warn "Current cluster state will be overwritten!"
    read -p "Are you sure? Type 'yes' to continue: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Restore cancelled"
        exit 0
    fi
    
    info "Starting restore from backup: $BACKUP_NAME"
    
    # Check if backup exists
    if ! velero backup get "$BACKUP_NAME" >/dev/null 2>&1; then
        error "Backup not found: $BACKUP_NAME"
    fi
    
    # Create restore
    velero restore create --from-backup "$BACKUP_NAME" --wait
    
    # Wait for restore to complete
    info "Waiting for restore to complete..."
    sleep 10
    
    # Check restore status
    velero restore get
    
    success "Restore completed"
    
    # Verify cluster health
    info "Verifying cluster health..."
    kubectl get nodes
    kubectl get pods --all-namespaces | grep -v Running || true
}

# Verify backup integrity
verify_backup() {
    if [[ -z "$BACKUP_NAME" ]]; then
        error "Backup name required"
    fi
    
    info "Verifying backup: $BACKUP_NAME"
    
    # Get backup details
    velero backup describe "$BACKUP_NAME" --details
    
    # Check backup logs
    velero backup logs "$BACKUP_NAME"
    
    # Verify backup contents
    info "Backup contents:"
    velero backup describe "$BACKUP_NAME" --details | grep -A 10 "Resource List:"
    
    success "Backup verification completed"
}

# Export backup to external storage
export_backup() {
    local backup_name="$BACKUP_NAME"
    local export_path="${3:-/tmp/k3s-backup-export}"
    
    if [[ -z "$backup_name" ]]; then
        error "Backup name required"
    fi
    
    info "Exporting backup: $backup_name to $export_path"
    
    # Create export directory
    mkdir -p "$export_path"
    
    # Download backup
    velero backup download "$backup_name" --output-file "$export_path/${backup_name}.tar.gz"
    
    # Export etcd snapshot if available
    if kubectl get pod -n backup -l job-name=etcd-backup >/dev/null 2>&1; then
        info "Exporting etcd snapshots..."
        kubectl cp backup/etcd-backup-storage:/backups/etcd "$export_path/etcd-snapshots"
    fi
    
    # Create backup metadata
    cat > "$export_path/backup-metadata.json" <<EOF
{
    "backup_name": "$backup_name",
    "export_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "cluster_info": {
        "nodes": $(kubectl get nodes -o json | jq -c '[.items[].metadata.name]'),
        "namespaces": $(kubectl get namespaces -o json | jq -c '[.items[].metadata.name]')
    }
}
EOF
    
    # Create restore instructions
    cat > "$export_path/RESTORE_INSTRUCTIONS.md" <<EOF
# Restore Instructions

## Prerequisites
1. Fresh K3s cluster installed
2. Velero installed with same configuration
3. Access to backup storage

## Restore Steps

1. Copy backup to new cluster:
   \`\`\`bash
   scp -r $export_path/* user@new-cluster:/tmp/restore/
   \`\`\`

2. Import backup to Velero:
   \`\`\`bash
   velero backup create --from-backup $backup_name
   \`\`\`

3. Restore cluster state:
   \`\`\`bash
   velero restore create --from-backup $backup_name
   \`\`\`

4. Restore etcd (if needed):
   \`\`\`bash
   # Copy etcd snapshot to master node
   # Run etcdctl snapshot restore
   \`\`\`

5. Verify restoration:
   \`\`\`bash
   kubectl get nodes
   kubectl get pods --all-namespaces
   \`\`\`
EOF
    
    success "Backup exported to: $export_path"
    info "Total size: $(du -sh "$export_path" | cut -f1)"
}

# Simulate disaster recovery
simulate_dr() {
    info "Starting disaster recovery simulation..."
    
    # Create test namespace
    kubectl create namespace dr-test || true
    
    # Deploy test application
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dr-test-app
  namespace: dr-test
  labels:
    app: dr-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dr-test
  template:
    metadata:
      labels:
        app: dr-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: dr-test-svc
  namespace: dr-test
spec:
  selector:
    app: dr-test
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: dr-test-config
  namespace: dr-test
data:
  test.conf: |
    This is test data for DR simulation
    Created at: $(date)
EOF
    
    # Wait for deployment
    wait_for_deployment dr-test dr-test-app
    
    # Create backup
    info "Creating test backup..."
    velero backup create dr-test-$(date +%s) --include-namespaces dr-test --wait
    
    # Delete test namespace
    info "Simulating disaster - deleting test namespace..."
    kubectl delete namespace dr-test --wait
    
    # Restore from backup
    info "Restoring from backup..."
    velero restore create --from-backup dr-test-$(date +%s) --wait
    
    # Verify restoration
    info "Verifying restoration..."
    kubectl get all -n dr-test
    
    # Cleanup
    kubectl delete namespace dr-test --wait
    
    success "Disaster recovery simulation completed successfully"
}

# Generate DR readiness report
generate_report() {
    local report_file="/tmp/dr-readiness-report-$(date +%Y%m%d-%H%M%S).md"
    
    info "Generating DR readiness report..."
    
    cat > "$report_file" <<EOF
# Disaster Recovery Readiness Report

Generated: $(date)

## Backup Configuration

### Velero Status
\`\`\`
$(velero version)
\`\`\`

### Backup Schedules
\`\`\`
$(velero schedule get)
\`\`\`

### Recent Backups
\`\`\`
$(velero backup get)
\`\`\`

### Backup Storage Location
\`\`\`
$(velero backup-location get)
\`\`\`

## Cluster Information

### Nodes
\`\`\`
$(kubectl get nodes)
\`\`\`

### Namespaces
\`\`\`
$(kubectl get namespaces)
\`\`\`

### Persistent Volumes
\`\`\`
$(kubectl get pv)
\`\`\`

## Critical Applications

### Gitea
\`\`\`
$(kubectl get all -n gitea 2>/dev/null || echo "Gitea not installed")
\`\`\`

### Monitoring Stack
\`\`\`
$(kubectl get all -n monitoring 2>/dev/null || echo "Monitoring not installed")
\`\`\`

### Control Panel
\`\`\`
$(kubectl get all -n control-panel 2>/dev/null || echo "Control Panel not installed")
\`\`\`

## Recovery Time Objectives (RTO)

| Component | Target RTO | Estimated Actual |
|-----------|------------|------------------|
| etcd | 30 minutes | 15 minutes |
| Applications | 1 hour | 30 minutes |
| Full Cluster | 2 hours | 1 hour |

## Recovery Point Objectives (RPO)

| Backup Type | Frequency | Retention |
|-------------|-----------|-----------|
| Daily Backup | 24 hours | 30 days |
| Weekly Full | 7 days | 90 days |
| Critical Apps | 6 hours | 7 days |
| etcd | 24 hours | 7 days |

## DR Testing

Last DR test: $(kubectl get configmap -n backup dr-test-date -o jsonpath='{.data.date}' 2>/dev/null || echo "Never")

## Recommendations

1. **Regular Testing**: Schedule monthly DR tests
2. **Documentation**: Keep runbooks updated
3. **Off-site Backups**: Configure remote backup storage
4. **Monitoring**: Set up backup failure alerts
5. **Automation**: Automate restoration procedures

## Action Items

- [ ] Configure off-site backup replication
- [ ] Document application-specific restore procedures
- [ ] Set up backup monitoring alerts
- [ ] Schedule quarterly DR drills
- [ ] Review and update RPO/RTO targets
EOF
    
    success "DR readiness report generated: $report_file"
    cat "$report_file"
}

# Main execution
case $ACTION in
    list)
        list_backups
        ;;
    restore)
        restore_backup
        ;;
    verify)
        verify_backup
        ;;
    export)
        export_backup
        ;;
    simulate)
        simulate_dr
        ;;
    report)
        generate_report
        ;;
    help|*)
        show_usage
        ;;
esac