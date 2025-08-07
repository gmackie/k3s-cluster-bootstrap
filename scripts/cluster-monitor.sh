#!/bin/bash
# Cluster monitoring script for control panel integration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Output format: json, text, prometheus
FORMAT="${1:-json}"
METRIC_TYPE="${2:-all}"  # all, nodes, pods, storage

show_usage() {
    cat << EOF
Usage: $0 [format] [metric-type]

Cluster monitoring script

Arguments:
    format       Output format (json|text|prometheus) - default: json
    metric-type  Type of metrics (all|nodes|pods|storage) - default: all

Examples:
    # Get all metrics in JSON
    $0 json all

    # Get node metrics for Prometheus
    $0 prometheus nodes

    # Get human-readable text output
    $0 text all
EOF
}

# Collect node metrics
collect_node_metrics() {
    local nodes_json=$(kubectl get nodes -o json)
    local node_metrics=()
    
    # Try to get metrics from metrics-server
    local has_metrics=true
    kubectl top nodes --no-headers >/dev/null 2>&1 || has_metrics=false
    
    local metrics_data=""
    if [[ "$has_metrics" == "true" ]]; then
        metrics_data=$(kubectl top nodes --no-headers)
    fi
    
    # Process each node
    echo "$nodes_json" | jq -r '.items[] | @base64' | while read -r node_data; do
        local node_json=$(echo "$node_data" | base64 -d)
        local node_name=$(echo "$node_json" | jq -r '.metadata.name')
        local node_role="worker"
        
        # Check if master node
        if echo "$node_json" | jq -e '.metadata.labels["node-role.kubernetes.io/master"]' >/dev/null 2>&1; then
            node_role="master"
        fi
        
        # Get node conditions
        local ready=$(echo "$node_json" | jq -r '.status.conditions[] | select(.type=="Ready") | .status')
        local memory_pressure=$(echo "$node_json" | jq -r '.status.conditions[] | select(.type=="MemoryPressure") | .status')
        local disk_pressure=$(echo "$node_json" | jq -r '.status.conditions[] | select(.type=="DiskPressure") | .status')
        local pid_pressure=$(echo "$node_json" | jq -r '.status.conditions[] | select(.type=="PIDPressure") | .status')
        
        # Get capacity and allocatable resources
        local cpu_capacity=$(echo "$node_json" | jq -r '.status.capacity.cpu')
        local mem_capacity=$(echo "$node_json" | jq -r '.status.capacity.memory' | sed 's/Ki$//' | awk '{print int($1/1024)}')
        local storage_capacity=$(echo "$node_json" | jq -r '.status.capacity["ephemeral-storage"]' | sed 's/Ki$//' | awk '{print int($1/1024/1024)}')
        local pods_capacity=$(echo "$node_json" | jq -r '.status.capacity.pods')
        
        # Get current usage if metrics available
        local cpu_used="0"
        local cpu_percent="0"
        local mem_used="0"
        local mem_percent="0"
        
        if [[ "$has_metrics" == "true" ]]; then
            local node_metric=$(echo "$metrics_data" | grep "^$node_name " || echo "")
            if [[ -n "$node_metric" ]]; then
                cpu_used=$(echo "$node_metric" | awk '{print $2}' | sed 's/m$//')
                cpu_percent=$(echo "$node_metric" | awk '{print $3}' | sed 's/%$//')
                mem_used=$(echo "$node_metric" | awk '{print $4}' | sed 's/Mi$//')
                mem_percent=$(echo "$node_metric" | awk '{print $5}' | sed 's/%$//')
            fi
        fi
        
        # Get pod count on node
        local pod_count=$(kubectl get pods --all-namespaces --field-selector spec.nodeName="$node_name" --no-headers 2>/dev/null | wc -l)
        
        # Get node age
        local created=$(echo "$node_json" | jq -r '.metadata.creationTimestamp')
        local age_seconds=$(( $(date +%s) - $(date -d "$created" +%s) ))
        local age_days=$(( age_seconds / 86400 ))
        
        # Get provider info
        local provider="unknown"
        local instance_type="unknown"
        if echo "$node_json" | jq -e '.metadata.labels["instance.hetzner.cloud/type"]' >/dev/null 2>&1; then
            provider="hetzner"
            instance_type=$(echo "$node_json" | jq -r '.metadata.labels["instance.hetzner.cloud/type"]')
        fi
        
        # Output based on format
        case $FORMAT in
            json)
                cat <<EOF
{
    "name": "$node_name",
    "role": "$node_role",
    "ready": "$ready",
    "age_days": $age_days,
    "provider": "$provider",
    "instance_type": "$instance_type",
    "conditions": {
        "ready": "$ready",
        "memory_pressure": "$memory_pressure",
        "disk_pressure": "$disk_pressure",
        "pid_pressure": "$pid_pressure"
    },
    "capacity": {
        "cpu_cores": $cpu_capacity,
        "memory_mb": $mem_capacity,
        "storage_gb": $storage_capacity,
        "max_pods": $pods_capacity
    },
    "usage": {
        "cpu_millicores": $cpu_used,
        "cpu_percent": $cpu_percent,
        "memory_mb": $mem_used,
        "memory_percent": $mem_percent,
        "pod_count": $pod_count,
        "pod_percent": $(awk "BEGIN {printf \"%.1f\", ($pod_count / $pods_capacity) * 100}")
    }
},
EOF
                ;;
            prometheus)
                cat <<EOF
# Node metrics for $node_name
k3s_node_ready{node="$node_name",role="$node_role"} $([ "$ready" == "True" ] && echo 1 || echo 0)
k3s_node_cpu_cores{node="$node_name"} $cpu_capacity
k3s_node_memory_bytes{node="$node_name"} $(( mem_capacity * 1024 * 1024 ))
k3s_node_storage_bytes{node="$node_name"} $(( storage_capacity * 1024 * 1024 * 1024 ))
k3s_node_cpu_usage_millicores{node="$node_name"} $cpu_used
k3s_node_cpu_usage_percent{node="$node_name"} $cpu_percent
k3s_node_memory_usage_bytes{node="$node_name"} $(( mem_used * 1024 * 1024 ))
k3s_node_memory_usage_percent{node="$node_name"} $mem_percent
k3s_node_pod_count{node="$node_name"} $pod_count
k3s_node_pod_capacity{node="$node_name"} $pods_capacity
k3s_node_age_seconds{node="$node_name"} $age_seconds

EOF
                ;;
            text)
                echo "Node: $node_name ($node_role)"
                echo "  Status: $ready (Age: ${age_days}d)"
                echo "  Provider: $provider ($instance_type)"
                echo "  CPU: ${cpu_percent}% (${cpu_used}m / ${cpu_capacity} cores)"
                echo "  Memory: ${mem_percent}% (${mem_used}Mi / ${mem_capacity}Mi)"
                echo "  Pods: $pod_count / $pods_capacity"
                echo "  Conditions: Memory=$memory_pressure, Disk=$disk_pressure, PID=$pid_pressure"
                echo ""
                ;;
        esac
    done
}

# Collect pod metrics
collect_pod_metrics() {
    local pods_json=$(kubectl get pods --all-namespaces -o json)
    local namespace_summary=()
    
    # Get pod metrics if available
    local has_metrics=true
    kubectl top pods --all-namespaces --no-headers >/dev/null 2>&1 || has_metrics=false
    
    # Summary by namespace
    echo "$pods_json" | jq -r '
        .items | group_by(.metadata.namespace) | .[] | 
        {
            namespace: .[0].metadata.namespace,
            total: length,
            running: [.[] | select(.status.phase=="Running")] | length,
            pending: [.[] | select(.status.phase=="Pending")] | length,
            failed: [.[] | select(.status.phase=="Failed")] | length,
            succeeded: [.[] | select(.status.phase=="Succeeded")] | length
        }
    ' | while read -r ns_data; do
        case $FORMAT in
            json)
                echo "$ns_data,"
                ;;
            prometheus)
                local ns=$(echo "$ns_data" | jq -r '.namespace')
                local total=$(echo "$ns_data" | jq -r '.total')
                local running=$(echo "$ns_data" | jq -r '.running')
                local pending=$(echo "$ns_data" | jq -r '.pending')
                local failed=$(echo "$ns_data" | jq -r '.failed')
                echo "k3s_namespace_pod_count{namespace=\"$ns\",status=\"total\"} $total"
                echo "k3s_namespace_pod_count{namespace=\"$ns\",status=\"running\"} $running"
                echo "k3s_namespace_pod_count{namespace=\"$ns\",status=\"pending\"} $pending"
                echo "k3s_namespace_pod_count{namespace=\"$ns\",status=\"failed\"} $failed"
                ;;
            text)
                echo "$ns_data" | jq -r '"Namespace: \(.namespace) - Total: \(.total), Running: \(.running), Pending: \(.pending), Failed: \(.failed)"'
                ;;
        esac
    done
}

# Collect storage metrics
collect_storage_metrics() {
    local pvs_json=$(kubectl get pv -o json 2>/dev/null || echo '{"items":[]}')
    local pvcs_json=$(kubectl get pvc --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')
    
    # PV metrics
    echo "$pvs_json" | jq -r '.items[] | @base64' | while read -r pv_data; do
        local pv_json=$(echo "$pv_data" | base64 -d)
        local pv_name=$(echo "$pv_json" | jq -r '.metadata.name')
        local capacity=$(echo "$pv_json" | jq -r '.spec.capacity.storage' | sed 's/Gi$//')
        local phase=$(echo "$pv_json" | jq -r '.status.phase')
        local storage_class=$(echo "$pv_json" | jq -r '.spec.storageClassName // "none"')
        
        case $FORMAT in
            json)
                cat <<EOF
{
    "type": "pv",
    "name": "$pv_name",
    "capacity_gb": $capacity,
    "phase": "$phase",
    "storage_class": "$storage_class"
},
EOF
                ;;
            prometheus)
                echo "k3s_pv_capacity_bytes{pv=\"$pv_name\",storage_class=\"$storage_class\"} $(( capacity * 1024 * 1024 * 1024 ))"
                echo "k3s_pv_phase{pv=\"$pv_name\",phase=\"$phase\"} 1"
                ;;
            text)
                echo "PV: $pv_name - ${capacity}Gi ($phase) [$storage_class]"
                ;;
        esac
    done
}

# Main output
case $FORMAT in
    json)
        echo "{"
        
        if [[ "$METRIC_TYPE" == "all" || "$METRIC_TYPE" == "nodes" ]]; then
            echo '"nodes": ['
            collect_node_metrics | sed '$ s/,$//'
            echo '],'
        fi
        
        if [[ "$METRIC_TYPE" == "all" || "$METRIC_TYPE" == "pods" ]]; then
            echo '"pods": ['
            collect_pod_metrics | sed '$ s/,$//'
            echo '],'
        fi
        
        if [[ "$METRIC_TYPE" == "all" || "$METRIC_TYPE" == "storage" ]]; then
            echo '"storage": ['
            collect_storage_metrics | sed '$ s/,$//'
            echo '],'
        fi
        
        echo '"timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"'
        echo "}"
        ;;
        
    prometheus)
        echo "# K3s Cluster Metrics"
        echo "# Generated at $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo ""
        
        if [[ "$METRIC_TYPE" == "all" || "$METRIC_TYPE" == "nodes" ]]; then
            echo "# Node Metrics"
            collect_node_metrics
        fi
        
        if [[ "$METRIC_TYPE" == "all" || "$METRIC_TYPE" == "pods" ]]; then
            echo "# Pod Metrics"
            collect_pod_metrics
        fi
        
        if [[ "$METRIC_TYPE" == "all" || "$METRIC_TYPE" == "storage" ]]; then
            echo "# Storage Metrics"
            collect_storage_metrics
        fi
        ;;
        
    text)
        echo "K3s Cluster Status Report"
        echo "Generated: $(date)"
        echo "========================"
        echo ""
        
        if [[ "$METRIC_TYPE" == "all" || "$METRIC_TYPE" == "nodes" ]]; then
            echo "NODE STATUS:"
            echo "------------"
            collect_node_metrics
        fi
        
        if [[ "$METRIC_TYPE" == "all" || "$METRIC_TYPE" == "pods" ]]; then
            echo "POD STATUS:"
            echo "-----------"
            collect_pod_metrics
            echo ""
        fi
        
        if [[ "$METRIC_TYPE" == "all" || "$METRIC_TYPE" == "storage" ]]; then
            echo "STORAGE STATUS:"
            echo "---------------"
            collect_storage_metrics
        fi
        ;;
        
    *)
        show_usage
        exit 1
        ;;
esac