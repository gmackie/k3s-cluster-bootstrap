#!/bin/bash
# Remove a node from the K3s cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Configuration
NODE_NAME="${1:-}"
FORCE="${2:-false}"
PROVIDER="${PROVIDER:-local}"

show_usage() {
    cat << EOF
Usage: $0 <node-name> [force]

Remove a node from the K3s cluster

Arguments:
    node-name    Name of the node to remove
    force        Skip confirmation and drain timeout (true|false)

Environment Variables:
    PROVIDER     Provider (local|hetzner) - affects cleanup

Examples:
    # Remove node with confirmation
    $0 worker-1

    # Force remove without confirmation
    $0 worker-1 true

    # Remove Hetzner node (also deletes the server)
    PROVIDER=hetzner $0 worker-1
EOF
}

if [[ -z "$NODE_NAME" || "$1" == "--help" || "$1" == "-h" ]]; then
    show_usage
    exit 0
fi

# Check if node exists
if ! kubectl get node "$NODE_NAME" >/dev/null 2>&1; then
    error "Node $NODE_NAME not found in cluster"
fi

# Show node information
info "Node information:"
kubectl get node "$NODE_NAME" -o wide

# Get node details from inventory
NODE_INFO=$(grep "^${NODE_NAME}:" "${SCRIPT_DIR}/../.cluster/nodes.inventory" 2>/dev/null || echo "")
if [[ -n "$NODE_INFO" ]]; then
    NODE_IP=$(echo "$NODE_INFO" | cut -d: -f2)
    NODE_TYPE=$(echo "$NODE_INFO" | cut -d: -f3)
    IS_HETZNER=$(echo "$NODE_INFO" | grep -q "hetzner$" && echo "true" || echo "false")
else
    NODE_IP=""
    NODE_TYPE="unknown"
    IS_HETZNER="false"
fi

# Confirmation
if [[ "$FORCE" != "true" ]]; then
    warn "This will remove node $NODE_NAME from the cluster"
    if [[ "$PROVIDER" == "hetzner" || "$IS_HETZNER" == "true" ]]; then
        warn "This will also DELETE the Hetzner server!"
    fi
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cancelled"
        exit 0
    fi
fi

# Step 1: Cordon the node (prevent new pods)
info "Cordoning node $NODE_NAME..."
kubectl cordon "$NODE_NAME"

# Step 2: Drain the node (move pods to other nodes)
info "Draining node $NODE_NAME..."
if [[ "$FORCE" == "true" ]]; then
    kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --force --grace-period=30
else
    kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --force
fi

# Wait for pods to be moved
sleep 10

# Step 3: Delete the node from cluster
info "Removing node from cluster..."
kubectl delete node "$NODE_NAME"

# Step 4: Clean up the node (stop k3s, remove data)
if [[ -n "$NODE_IP" && "$NODE_IP" != "unknown" ]]; then
    info "Cleaning up node $NODE_IP..."
    
    # Try to connect and clean up
    if ssh -o ConnectTimeout=5 root@"$NODE_IP" echo "Connected" 2>/dev/null; then
        ssh root@"$NODE_IP" << 'EOF' || true
            # Stop and disable k3s
            systemctl stop k3s || systemctl stop k3s-agent || true
            systemctl disable k3s || systemctl disable k3s-agent || true
            
            # Uninstall k3s
            if [[ -f /usr/local/bin/k3s-uninstall.sh ]]; then
                /usr/local/bin/k3s-uninstall.sh
            elif [[ -f /usr/local/bin/k3s-agent-uninstall.sh ]]; then
                /usr/local/bin/k3s-agent-uninstall.sh
            fi
            
            # Clean up k3s data
            rm -rf /etc/rancher/k3s
            rm -rf /var/lib/rancher/k3s
            rm -rf /var/lib/kubelet
            rm -f /etc/systemd/system/k3s*.service
            
            systemctl daemon-reload
EOF
    else
        warn "Unable to connect to node for cleanup"
    fi
fi

# Step 5: Provider-specific cleanup
if [[ "$PROVIDER" == "hetzner" || "$IS_HETZNER" == "true" ]]; then
    if command_exists hcloud; then
        info "Deleting Hetzner server $NODE_NAME..."
        
        # Delete the server
        if hcloud server describe "$NODE_NAME" >/dev/null 2>&1; then
            hcloud server delete "$NODE_NAME"
            success "Hetzner server deleted"
        else
            warn "Hetzner server $NODE_NAME not found"
        fi
    else
        warn "hcloud CLI not found, cannot delete Hetzner server"
    fi
fi

# Step 6: Update inventory
if [[ -f "${SCRIPT_DIR}/../.cluster/nodes.inventory" ]]; then
    info "Updating node inventory..."
    grep -v "^${NODE_NAME}:" "${SCRIPT_DIR}/../.cluster/nodes.inventory" > "${SCRIPT_DIR}/../.cluster/nodes.inventory.tmp" || true
    mv "${SCRIPT_DIR}/../.cluster/nodes.inventory.tmp" "${SCRIPT_DIR}/../.cluster/nodes.inventory"
fi

success "Node $NODE_NAME removed from cluster"

# Show remaining nodes
info "Remaining cluster nodes:"
kubectl get nodes -o wide

# Check cluster health
info "Checking cluster health..."
kubectl get pods --all-namespaces | grep -E "(Pending|Error|CrashLoop)" || echo "All pods healthy"