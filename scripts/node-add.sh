#!/bin/bash
# Add a new node to the K3s cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Configuration
NODE_TYPE="${1:-worker}"
NODE_NAME="${2:-}"
NODE_IP="${3:-}"
NODE_LABELS="${4:-}"
PROVIDER="${PROVIDER:-local}"  # local or hetzner

show_usage() {
    cat << EOF
Usage: $0 <node-type> [node-name] [node-ip] [labels]

Add a new node to the K3s cluster

Arguments:
    node-type    Type of node to add (master|worker)
    node-name    Name for the new node (optional, auto-generated if not provided)
    node-ip      IP address of the node (required for local, auto for hetzner)
    labels       Comma-separated labels (e.g., "role=compute,zone=eu-west")

Environment Variables:
    PROVIDER           Provider to use (local|hetzner) - default: local
    HETZNER_API_TOKEN  Required for Hetzner provider
    SERVER_TYPE        Hetzner server type (default: cpx11)

Examples:
    # Add local worker node
    $0 worker worker-1 192.168.1.100

    # Add Hetzner worker node
    PROVIDER=hetzner $0 worker

    # Add node with labels
    $0 worker gpu-node-1 192.168.1.101 "gpu=true,workload=ml"
EOF
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_usage
    exit 0
fi

# Validate node type
if [[ "$NODE_TYPE" != "master" && "$NODE_TYPE" != "worker" ]]; then
    error "Invalid node type: $NODE_TYPE. Must be 'master' or 'worker'"
fi

# Generate node name if not provided
if [[ -z "$NODE_NAME" ]]; then
    NODE_NAME="${NODE_TYPE}-$(date +%s)"
    info "Generated node name: $NODE_NAME"
fi

# Get cluster information
if [[ ! -f "${SCRIPT_DIR}/../.cluster/master-ip" ]]; then
    error "Cluster not initialized. Run bootstrap.sh first."
fi

MASTER_IP=$(cat "${SCRIPT_DIR}/../.cluster/master-ip")
NODE_TOKEN=$(cat "${SCRIPT_DIR}/../.cluster/node-token")

# Provider-specific node creation
case $PROVIDER in
    local)
        add_local_node
        ;;
    hetzner)
        add_hetzner_node
        ;;
    *)
        error "Unknown provider: $PROVIDER"
        ;;
esac

# Function to add local node
add_local_node() {
    if [[ -z "$NODE_IP" ]]; then
        error "Node IP is required for local provider"
    fi
    
    info "Adding local node: $NODE_NAME ($NODE_IP)"
    
    # Generate installation script
    cat > /tmp/install-node.sh << EOF
#!/bin/bash
set -e

# Install K3s on the node
export MASTER_IP="$MASTER_IP"
export NODE_NAME="$NODE_NAME"
export NODE_TYPE="$NODE_TYPE"
export NODE_LABELS="$NODE_LABELS"
export K3S_TOKEN="$NODE_TOKEN"

$(cat "${SCRIPT_DIR}/../components/base/install.sh")
EOF
    
    # Copy and execute installation script on remote node
    info "Copying installation files to node..."
    scp -r /tmp/install-node.sh root@${NODE_IP}:/tmp/
    scp -r "${SCRIPT_DIR}/../lib" root@${NODE_IP}:/tmp/
    
    info "Installing K3s on node..."
    ssh root@${NODE_IP} "chmod +x /tmp/install-node.sh && /tmp/install-node.sh"
    
    # Verify node joined
    sleep 10
    if kubectl get node "$NODE_NAME" >/dev/null 2>&1; then
        success "Node $NODE_NAME successfully added to cluster"
        kubectl get node "$NODE_NAME" -o wide
    else
        error "Failed to verify node $NODE_NAME in cluster"
    fi
    
    # Update node inventory
    echo "${NODE_NAME}:${NODE_IP}:${NODE_TYPE}:${NODE_LABELS}" >> "${SCRIPT_DIR}/../.cluster/nodes.inventory"
}

# Function to add Hetzner node
add_hetzner_node() {
    if [[ -z "$HETZNER_API_TOKEN" ]]; then
        error "HETZNER_API_TOKEN is required for Hetzner provider"
    fi
    
    info "Creating Hetzner node: $NODE_NAME"
    
    # Server configuration
    SERVER_TYPE="${SERVER_TYPE:-cpx11}"
    LOCATION="${LOCATION:-nbg1}"
    IMAGE="${IMAGE:-ubuntu-22.04}"
    
    # Create the server
    hcloud server create \
        --name "$NODE_NAME" \
        --type "$SERVER_TYPE" \
        --image "$IMAGE" \
        --location "$LOCATION" \
        --ssh-key "k3s-cluster-key" \
        --label "k3s-role=$NODE_TYPE" \
        --label "k3s-cluster=true" \
        --start-after-create
    
    # Wait for server to be ready
    info "Waiting for server to be ready..."
    sleep 30
    
    # Get server IP
    NODE_IP=$(hcloud server ip "$NODE_NAME")
    info "Server created with IP: $NODE_IP"
    
    # Wait for SSH
    while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ~/.ssh/k3s-cluster root@"$NODE_IP" echo "SSH ready" 2>/dev/null; do
        sleep 5
    done
    
    # Install K3s on the node
    info "Installing K3s on Hetzner node..."
    ssh -i ~/.ssh/k3s-cluster root@"$NODE_IP" << EOF
        # Update system
        apt-get update
        apt-get upgrade -y
        
        # Install K3s
        export INSTALL_K3S_EXEC="agent --server https://${MASTER_IP}:6443 --token ${NODE_TOKEN} --node-name ${NODE_NAME}"
        
        if [[ -n "$NODE_LABELS" ]]; then
            export INSTALL_K3S_EXEC="\$INSTALL_K3S_EXEC --node-label $NODE_LABELS"
        fi
        
        if [[ "$NODE_TYPE" == "worker" ]]; then
            # Add worker-specific labels
            export INSTALL_K3S_EXEC="\$INSTALL_K3S_EXEC --node-label node-role.kubernetes.io/worker=true"
        fi
        
        curl -sfL https://get.k3s.io | sh -
EOF
    
    # Configure Hetzner Cloud Controller Manager for the node
    kubectl label node "$NODE_NAME" "instance.hetzner.cloud/id=$(hcloud server describe -o json $NODE_NAME | jq -r .id)" || true
    kubectl label node "$NODE_NAME" "instance.hetzner.cloud/type=$SERVER_TYPE" || true
    
    # Verify node joined
    sleep 10
    if kubectl get node "$NODE_NAME" >/dev/null 2>&1; then
        success "Node $NODE_NAME successfully added to cluster"
        kubectl get node "$NODE_NAME" -o wide
        
        # Update node inventory
        echo "${NODE_NAME}:${NODE_IP}:${NODE_TYPE}:${NODE_LABELS}:hetzner" >> "${SCRIPT_DIR}/../.cluster/nodes.inventory"
    else
        error "Failed to verify node $NODE_NAME in cluster"
    fi
}

# Main execution
case $PROVIDER in
    local)
        add_local_node
        ;;
    hetzner)
        add_hetzner_node
        ;;
esac

# Show cluster status
info "Current cluster nodes:"
kubectl get nodes -o wide

# Clean up
rm -f /tmp/install-node.sh