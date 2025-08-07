#!/bin/bash
# Cluster scaling automation script - can be called by control panel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Default thresholds
CPU_SCALE_UP_THRESHOLD="${CPU_SCALE_UP_THRESHOLD:-80}"
CPU_SCALE_DOWN_THRESHOLD="${CPU_SCALE_DOWN_THRESHOLD:-20}"
MEM_SCALE_UP_THRESHOLD="${MEM_SCALE_UP_THRESHOLD:-80}"
MEM_SCALE_DOWN_THRESHOLD="${MEM_SCALE_DOWN_THRESHOLD:-20}"
MIN_NODES="${MIN_NODES:-1}"
MAX_NODES="${MAX_NODES:-10}"
PROVIDER="${PROVIDER:-hetzner}"

# Action can be: check, scale-up, scale-down, recommend
ACTION="${1:-check}"

show_usage() {
    cat << EOF
Usage: $0 [action]

Cluster scaling automation script

Actions:
    check       Check cluster metrics and provide recommendations
    scale-up    Add a new node to the cluster
    scale-down  Remove a node from the cluster
    recommend   Get scaling recommendations in JSON format

Environment Variables:
    CPU_SCALE_UP_THRESHOLD    CPU % to trigger scale up (default: 80)
    CPU_SCALE_DOWN_THRESHOLD  CPU % to trigger scale down (default: 20)
    MEM_SCALE_UP_THRESHOLD    Memory % to trigger scale up (default: 80)
    MEM_SCALE_DOWN_THRESHOLD  Memory % to trigger scale down (default: 20)
    MIN_NODES                 Minimum number of nodes (default: 1)
    MAX_NODES                 Maximum number of nodes (default: 10)
    PROVIDER                  Provider for new nodes (default: hetzner)

Examples:
    # Check cluster and get recommendations
    $0 check

    # Scale up with custom threshold
    CPU_SCALE_UP_THRESHOLD=70 $0 scale-up

    # Get JSON recommendations for control panel
    $0 recommend
EOF
}

# Get cluster metrics
get_cluster_metrics() {
    # Get node metrics
    local nodes_json=$(kubectl get nodes -o json)
    local metrics_json=$(kubectl top nodes --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$metrics_json" ]]; then
        error "Metrics server not available. Install metrics-server first."
    fi
    
    # Calculate cluster-wide metrics
    local total_cpu_cores=0
    local total_cpu_used=0
    local total_memory=0
    local total_memory_used=0
    local node_count=0
    local worker_nodes=()
    
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then continue; fi
        
        local node_name=$(echo "$line" | awk '{print $1}')
        local cpu_used=$(echo "$line" | awk '{print $2}' | sed 's/m$//')
        local cpu_percent=$(echo "$line" | awk '{print $3}' | sed 's/%$//')
        local mem_used=$(echo "$line" | awk '{print $4}' | sed 's/Mi$//')
        local mem_percent=$(echo "$line" | awk '{print $5}' | sed 's/%$//')
        
        # Get node capacity
        local node_info=$(echo "$nodes_json" | jq -r ".items[] | select(.metadata.name==\"$node_name\")")
        local cpu_capacity=$(echo "$node_info" | jq -r '.status.capacity.cpu // 1')
        local mem_capacity=$(echo "$node_info" | jq -r '.status.capacity.memory' | sed 's/Ki$//' | awk '{print int($1/1024)}')
        
        # Check if worker node
        local is_worker=$(echo "$node_info" | jq -r '.metadata.labels["node-role.kubernetes.io/master"] // "false"')
        if [[ "$is_worker" == "false" || "$is_worker" == "null" ]]; then
            worker_nodes+=("$node_name:$cpu_percent:$mem_percent")
        fi
        
        # Accumulate totals
        total_cpu_cores=$((total_cpu_cores + cpu_capacity))
        total_cpu_used=$((total_cpu_used + cpu_used))
        total_memory=$((total_memory + mem_capacity))
        total_memory_used=$((total_memory_used + mem_used))
        node_count=$((node_count + 1))
    done <<< "$metrics_json"
    
    # Calculate percentages
    local cpu_percent=$(awk "BEGIN {printf \"%.1f\", ($total_cpu_used / ($total_cpu_cores * 1000)) * 100}")
    local mem_percent=$(awk "BEGIN {printf \"%.1f\", ($total_memory_used / $total_memory) * 100}")
    
    # Return metrics
    echo "{
        \"node_count\": $node_count,
        \"worker_count\": ${#worker_nodes[@]},
        \"total_cpu_cores\": $total_cpu_cores,
        \"total_memory_mb\": $total_memory,
        \"cpu_percent\": $cpu_percent,
        \"memory_percent\": $mem_percent,
        \"worker_nodes\": [$(printf '"%s",' "${worker_nodes[@]}" | sed 's/,$//')]
    }"
}

# Get scaling recommendation
get_recommendation() {
    local metrics=$(get_cluster_metrics)
    local node_count=$(echo "$metrics" | jq -r '.node_count')
    local worker_count=$(echo "$metrics" | jq -r '.worker_count')
    local cpu_percent=$(echo "$metrics" | jq -r '.cpu_percent')
    local mem_percent=$(echo "$metrics" | jq -r '.memory_percent')
    
    local recommendation="none"
    local reason=""
    
    # Check scale up conditions
    if (( $(echo "$cpu_percent > $CPU_SCALE_UP_THRESHOLD" | bc -l) )) || \
       (( $(echo "$mem_percent > $MEM_SCALE_UP_THRESHOLD" | bc -l) )); then
        if [[ $worker_count -lt $MAX_NODES ]]; then
            recommendation="scale-up"
            reason="High resource usage - CPU: ${cpu_percent}%, Memory: ${mem_percent}%"
        else
            recommendation="at-max"
            reason="High resource usage but already at maximum nodes ($MAX_NODES)"
        fi
    # Check scale down conditions
    elif (( $(echo "$cpu_percent < $CPU_SCALE_DOWN_THRESHOLD" | bc -l) )) && \
         (( $(echo "$mem_percent < $MEM_SCALE_DOWN_THRESHOLD" | bc -l) )); then
        if [[ $worker_count -gt $MIN_NODES ]]; then
            recommendation="scale-down"
            reason="Low resource usage - CPU: ${cpu_percent}%, Memory: ${mem_percent}%"
        else
            recommendation="at-min"
            reason="Low resource usage but already at minimum nodes ($MIN_NODES)"
        fi
    else
        reason="Resource usage within thresholds - CPU: ${cpu_percent}%, Memory: ${mem_percent}%"
    fi
    
    echo "{
        \"recommendation\": \"$recommendation\",
        \"reason\": \"$reason\",
        \"metrics\": $metrics,
        \"thresholds\": {
            \"cpu_scale_up\": $CPU_SCALE_UP_THRESHOLD,
            \"cpu_scale_down\": $CPU_SCALE_DOWN_THRESHOLD,
            \"mem_scale_up\": $MEM_SCALE_UP_THRESHOLD,
            \"mem_scale_down\": $MEM_SCALE_DOWN_THRESHOLD,
            \"min_nodes\": $MIN_NODES,
            \"max_nodes\": $MAX_NODES
        }
    }"
}

# Scale up the cluster
scale_up() {
    info "Scaling up cluster..."
    
    local timestamp=$(date +%s)
    local node_name="worker-auto-${timestamp}"
    
    # Call node-add script
    PROVIDER="$PROVIDER" "${SCRIPT_DIR}/node-add.sh" worker "$node_name" "" "autoscaled=true"
    
    # Log scaling event
    echo "$(date -u +"%Y-%m-%d %H:%M:%S UTC") SCALE_UP $node_name" >> "${SCRIPT_DIR}/../.cluster/scaling.log"
}

# Scale down the cluster
scale_down() {
    info "Scaling down cluster..."
    
    local metrics=$(get_cluster_metrics)
    local worker_nodes=($(echo "$metrics" | jq -r '.worker_nodes[]' | grep "autoscaled=true" | cut -d: -f1))
    
    if [[ ${#worker_nodes[@]} -eq 0 ]]; then
        # No autoscaled nodes, find least loaded worker
        worker_nodes=($(echo "$metrics" | jq -r '.worker_nodes[]' | sort -t: -k2,2n -k3,3n | head -1 | cut -d: -f1))
    fi
    
    if [[ ${#worker_nodes[@]} -eq 0 ]]; then
        warn "No suitable nodes to remove"
        return 1
    fi
    
    local node_to_remove="${worker_nodes[0]}"
    info "Removing node: $node_to_remove"
    
    # Call node-remove script
    PROVIDER="$PROVIDER" "${SCRIPT_DIR}/node-remove.sh" "$node_to_remove" true
    
    # Log scaling event
    echo "$(date -u +"%Y-%m-%d %H:%M:%S UTC") SCALE_DOWN $node_to_remove" >> "${SCRIPT_DIR}/../.cluster/scaling.log"
}

# Main execution
case $ACTION in
    check)
        info "Checking cluster metrics..."
        recommendation=$(get_recommendation)
        
        echo "Cluster Status:"
        echo "$recommendation" | jq -r '
            "Nodes: \(.metrics.node_count) (Workers: \(.metrics.worker_count))",
            "CPU Usage: \(.metrics.cpu_percent)% of \(.metrics.total_cpu_cores) cores",
            "Memory Usage: \(.metrics.memory_percent)% of \(.metrics.total_memory_mb) MB",
            "",
            "Recommendation: \(.recommendation)",
            "Reason: \(.reason)"
        '
        ;;
        
    recommend)
        # Output JSON for control panel
        get_recommendation
        ;;
        
    scale-up)
        recommendation=$(get_recommendation)
        if [[ $(echo "$recommendation" | jq -r '.recommendation') == "scale-up" ]]; then
            scale_up
        else
            warn "Scale up not recommended"
            echo "$recommendation" | jq -r '.reason'
            exit 1
        fi
        ;;
        
    scale-down)
        recommendation=$(get_recommendation)
        if [[ $(echo "$recommendation" | jq -r '.recommendation') == "scale-down" ]]; then
            scale_down
        else
            warn "Scale down not recommended"
            echo "$recommendation" | jq -r '.reason'
            exit 1
        fi
        ;;
        
    *)
        show_usage
        exit 1
        ;;
esac