#!/bin/bash
set -euo pipefail

# Script to add a worker node to existing K3s cluster

echo "=== K3s Worker Node Setup ==="
echo

# Check if running on master or worker
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <master-ip> [worker-hostname]"
    echo "Example: $0 5.78.106.236 k3s-worker-1"
    exit 1
fi

MASTER_IP=$1
WORKER_HOSTNAME=${2:-k3s-worker-$(date +%s)}
K3S_VERSION="v1.33.3+k3s1"

echo "Master IP: $MASTER_IP"
echo "Worker hostname: $WORKER_HOSTNAME"
echo

# Function to run on master node
generate_join_command() {
    echo "=== Run this on the MASTER node (${MASTER_IP}) ==="
    echo
    echo "ssh root@${MASTER_IP}"
    echo
    echo "# Get the node token:"
    echo "cat /var/lib/rancher/k3s/server/node-token"
    echo
    echo "# Or generate full join command:"
    echo "echo \"curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=\$(cat /var/lib/rancher/k3s/server/node-token) sh -s - agent\""
    echo
    echo "=== Copy the token or command above ==="
}

# Function to run on worker node
setup_worker() {
    echo "=== Setting up worker node ==="
    
    # Set hostname
    echo "Setting hostname to ${WORKER_HOSTNAME}..."
    hostnamectl set-hostname ${WORKER_HOSTNAME}
    
    # Update system
    echo "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    
    # Install required packages
    echo "Installing required packages..."
    apt-get install -y curl wget software-properties-common apt-transport-https ca-certificates gnupg lsb-release
    
    # Configure kernel modules
    echo "Configuring kernel modules..."
    cat <<EOF | tee /etc/modules-load.d/k3s.conf
br_netfilter
ip_conntrack
EOF
    
    modprobe br_netfilter
    modprobe ip_conntrack
    
    # Configure sysctl
    echo "Configuring sysctl..."
    cat <<EOF | tee /etc/sysctl.d/k3s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    
    sysctl --system
    
    # Configure firewall
    echo "Configuring firewall..."
    ufw allow 10250/tcp  # Kubelet API
    ufw allow 10255/tcp  # Read-only Kubelet API
    ufw allow 8472/udp   # Flannel VXLAN
    ufw allow 51820/udp  # Flannel WireGuard
    ufw allow 51821/udp  # Flannel WireGuard
    
    echo
    echo "=== Worker node prepared ==="
    echo
    echo "Now run the K3s install command with the token from the master:"
    echo
    echo "K3S_URL='https://${MASTER_IP}:6443' K3S_TOKEN='<TOKEN-FROM-MASTER>' sh -c 'curl -sfL https://get.k3s.io | sh -s - agent'"
    echo
    echo "Or if you have the full command from master, just run it."
}

# Main logic
if [[ $(hostname -I | awk '{print $1}') == "${MASTER_IP}" ]]; then
    echo "Running on master node"
    generate_join_command
else
    echo "Setting up worker node"
    setup_worker
fi

echo
echo "=== After worker joins ==="
echo "Verify on master with: kubectl get nodes"
echo
echo "=== Labeling the worker node ==="
echo "kubectl label node ${WORKER_HOSTNAME} node-role.kubernetes.io/worker=true"
echo
echo "=== To prefer scheduling on worker ==="
echo "kubectl label node ${WORKER_HOSTNAME} workload=preferred"