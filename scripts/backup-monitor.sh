#!/bin/bash
# Monitor backup health and status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

FORMAT="${1:-summary}"

show_usage() {
    cat << EOF
Usage: $0 [format]

Monitor backup system health and status

Formats:
    summary     Overview of backup status (default)
    detailed    Detailed backup information
    json        JSON output for automation
    prometheus  Prometheus metrics format

Examples:
    # Get backup summary
    $0 summary

    # Get detailed information
    $0 detailed

    # Get JSON for control panel
    $0 json

    # Get Prometheus metrics
    $0 prometheus
EOF
}

# Get backup statistics
get_backup_stats() {
    local total_backups=$(velero backup get -o json | jq '.items | length')
    local successful_backups=$(velero backup get -o json | jq '[.items[] | select(.status.phase=="Completed")] | length')
    local failed_backups=$(velero backup get -o json | jq '[.items[] | select(.status.phase=="Failed")] | length')
    local partial_backups=$(velero backup get -o json | jq '[.items[] | select(.status.phase=="PartiallyFailed")] | length')
    
    # Get latest backup time
    local latest_backup=$(velero backup get -o json | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.creationTimestamp // "Never"')
    
    # Get backup sizes
    local total_size=0
    if [[ -f "${SCRIPT_DIR}/../.cluster/backup/sizes.json" ]]; then
        total_size=$(jq -r '.total_size // 0' "${SCRIPT_DIR}/../.cluster/backup/sizes.json")
    fi
    
    echo "{
        \"total_backups\": $total_backups,
        \"successful_backups\": $successful_backups,
        \"failed_backups\": $failed_backups,
        \"partial_backups\": $partial_backups,
        \"latest_backup\": \"$latest_backup\",
        \"total_size_gb\": $(awk "BEGIN {printf \"%.2f\", $total_size / 1024 / 1024 / 1024}")
    }"
}

# Check schedule health
check_schedules() {
    local schedules=$(velero schedule get -o json)
    local schedule_status=()
    
    echo "$schedules" | jq -r '.items[] | @base64' | while read -r schedule_data; do
        local schedule=$(echo "$schedule_data" | base64 -d)
        local name=$(echo "$schedule" | jq -r '.metadata.name')
        local last_backup=$(echo "$schedule" | jq -r '.status.lastBackup // "Never"')
        local phase=$(echo "$schedule" | jq -r '.status.phase // "Unknown"')
        
        echo "{
            \"name\": \"$name\",
            \"last_backup\": \"$last_backup\",
            \"phase\": \"$phase\"
        }"
    done
}

# Summary format
show_summary() {
    info "=== Backup System Status ==="
    echo ""
    
    # Velero status
    if kubectl get deployment -n backup velero >/dev/null 2>&1; then
        local velero_ready=$(kubectl get deployment -n backup velero -o jsonpath='{.status.readyReplicas}')
        local velero_desired=$(kubectl get deployment -n backup velero -o jsonpath='{.spec.replicas}')
        
        if [[ "$velero_ready" == "$velero_desired" ]]; then
            success "Velero: Running ($velero_ready/$velero_desired replicas)"
        else
            error "Velero: Degraded ($velero_ready/$velero_desired replicas)"
        fi
    else
        error "Velero: Not installed"
        return 1
    fi
    
    # Backup statistics
    local stats=$(get_backup_stats)
    echo ""
    info "Backup Statistics:"
    echo "  Total backups: $(echo "$stats" | jq -r '.total_backups')"
    echo "  Successful: $(echo "$stats" | jq -r '.successful_backups')"
    echo "  Failed: $(echo "$stats" | jq -r '.failed_backups')"
    echo "  Partial: $(echo "$stats" | jq -r '.partial_backups')"
    echo "  Latest: $(echo "$stats" | jq -r '.latest_backup')"
    echo "  Total size: $(echo "$stats" | jq -r '.total_size_gb') GB"
    
    # Schedule status
    echo ""
    info "Backup Schedules:"
    velero schedule get | tail -n +2 | while read line; do
        echo "  $line"
    done
    
    # Recent backups
    echo ""
    info "Recent Backups (last 5):"
    velero backup get | head -6 | tail -n +2
    
    # Storage status
    echo ""
    info "Backup Storage:"
    velero backup-location get | tail -n +2
}

# Detailed format
show_detailed() {
    show_summary
    
    echo ""
    info "=== Detailed Backup Information ==="
    
    # Failed backups details
    local failed_backups=$(velero backup get -o json | jq -r '.items[] | select(.status.phase=="Failed") | .metadata.name')
    if [[ -n "$failed_backups" ]]; then
        echo ""
        warn "Failed Backups:"
        echo "$failed_backups" | while read backup; do
            echo ""
            echo "Backup: $backup"
            velero backup logs "$backup" | tail -20
        done
    fi
    
    # Schedule details
    echo ""
    info "Schedule Configuration:"
    velero schedule get -o yaml | grep -E "name:|schedule:|ttl:"
    
    # Volume snapshot status
    echo ""
    info "Volume Snapshots:"
    kubectl get volumesnapshot --all-namespaces 2>/dev/null || echo "No volume snapshots found"
    
    # etcd backup status
    echo ""
    info "etcd Backup Status:"
    kubectl get cronjob -n backup etcd-backup 2>/dev/null || echo "etcd backup not configured"
}

# JSON format
show_json() {
    local stats=$(get_backup_stats)
    local schedules=$(check_schedules)
    local velero_status="unknown"
    
    if kubectl get deployment -n backup velero >/dev/null 2>&1; then
        local ready=$(kubectl get deployment -n backup velero -o jsonpath='{.status.readyReplicas}')
        local desired=$(kubectl get deployment -n backup velero -o jsonpath='{.spec.replicas}')
        if [[ "$ready" == "$desired" ]]; then
            velero_status="healthy"
        else
            velero_status="degraded"
        fi
    else
        velero_status="not_installed"
    fi
    
    cat <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "velero_status": "$velero_status",
    "statistics": $stats,
    "schedules": [$(echo "$schedules" | paste -sd, -)]
}
EOF
}

# Prometheus format
show_prometheus() {
    local stats=$(get_backup_stats)
    local timestamp=$(date +%s)
    
    cat <<EOF
# HELP backup_total_count Total number of backups
# TYPE backup_total_count gauge
backup_total_count $(echo "$stats" | jq -r '.total_backups')

# HELP backup_successful_count Number of successful backups
# TYPE backup_successful_count gauge
backup_successful_count $(echo "$stats" | jq -r '.successful_backups')

# HELP backup_failed_count Number of failed backups
# TYPE backup_failed_count gauge
backup_failed_count $(echo "$stats" | jq -r '.failed_backups')

# HELP backup_partial_count Number of partially failed backups
# TYPE backup_partial_count gauge
backup_partial_count $(echo "$stats" | jq -r '.partial_backups')

# HELP backup_storage_bytes Total backup storage size in bytes
# TYPE backup_storage_bytes gauge
backup_storage_bytes $(echo "$stats" | jq -r '.total_size_gb * 1024 * 1024 * 1024')

# HELP backup_last_timestamp Timestamp of last backup
# TYPE backup_last_timestamp gauge
backup_last_timestamp $(date -d "$(echo "$stats" | jq -r '.latest_backup')" +%s 2>/dev/null || echo 0)

# HELP backup_velero_up Velero deployment status
# TYPE backup_velero_up gauge
backup_velero_up $(kubectl get deployment -n backup velero >/dev/null 2>&1 && echo 1 || echo 0)
EOF
}

# Main execution
case $FORMAT in
    summary)
        show_summary
        ;;
    detailed)
        show_detailed
        ;;
    json)
        show_json
        ;;
    prometheus)
        show_prometheus
        ;;
    help|*)
        show_usage
        ;;
esac