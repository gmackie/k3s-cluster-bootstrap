#!/bin/bash
set -euo pipefail

# Hetzner Cloud CLI script to create worker node with private networking

echo "=== Hetzner K3s Worker Node Setup (Private Network) ==="
echo

# Check for hcloud CLI
if ! command -v hcloud &> /dev/null; then
    echo "Error: hcloud CLI not found. Install it first:"
    echo "brew install hcloud"
    exit 1
fi

# Configuration
WORKER_NAME=${1:-k3s-worker-1}
SERVER_TYPE=${2:-cpx31}  # 4 vCPU, 8GB RAM, 160GB SSD
LOCATION="hil"  # Same as master
IMAGE="ubuntu-24.04"
MASTER_IP="5.78.106.236"
NETWORK_NAME="k3s-network"
NETWORK_SUBNET="10.0.0.0/16"

echo "Creating worker node:"
echo "  Name: ${WORKER_NAME}"
echo "  Type: ${SERVER_TYPE}"
echo "  Location: ${LOCATION}"
echo

# Create private network if it doesn't exist
if ! hcloud network describe "${NETWORK_NAME}" &>/dev/null; then
    echo "Creating private network..."
    hcloud network create \
        --name "${NETWORK_NAME}" \
        --ip-range "${NETWORK_SUBNET}"
    
    # Create subnet
    hcloud network add-subnet "${NETWORK_NAME}" \
        --type cloud \
        --network-zone eu-central \
        --ip-range "${NETWORK_SUBNET}"
fi

# Attach master to private network if not already attached
MASTER_IN_NETWORK=$(hcloud server describe k3s-master-1 -o json | jq -r ".private_net[0].network // empty")
if [[ -z "$MASTER_IN_NETWORK" ]]; then
    echo "Attaching master node to private network..."
    hcloud server attach-to-network k3s-master-1 \
        --network "${NETWORK_NAME}" \
        --ip 10.0.0.2
fi

# Get next available IP
WORKER_PRIVATE_IP="10.0.0.$((2 + $(hcloud server list -o json | jq '[.[] | select(.labels.purpose == "k3s-worker")] | length')))"

# Create the server without public IP
echo "Creating Hetzner server without public IP..."
hcloud server create \
    --name "${WORKER_NAME}" \
    --type "${SERVER_TYPE}" \
    --image "${IMAGE}" \
    --location "${LOCATION}" \
    --ssh-key k3s-cluster-key \
    --label purpose=k3s-worker \
    --network "${NETWORK_NAME}" \
    --no-public-ipv4 \
    --no-public-ipv6

# Attach to private network with specific IP
echo "Configuring private network IP..."
hcloud server attach-to-network "${WORKER_NAME}" \
    --network "${NETWORK_NAME}" \
    --ip "${WORKER_PRIVATE_IP}"

echo "Worker node created with private IP: ${WORKER_PRIVATE_IP}"

# Wait for server to be ready
echo "Waiting for server to be ready..."
sleep 30

# Get K3s token from master
echo "Getting K3s token from master..."
K3S_TOKEN=$(ssh root@${MASTER_IP} "cat /var/lib/rancher/k3s/server/node-token")

# Get master's private IP
MASTER_PRIVATE_IP="10.0.0.2"

# Setup worker node via master's SSH (jump host)
echo "Setting up worker node via master..."
ssh root@${MASTER_IP} << EOF
# First, ensure master can reach worker on private network
ping -c 3 ${WORKER_PRIVATE_IP}

# SSH to worker via private network
ssh -o StrictHostKeyChecking=no root@${WORKER_PRIVATE_IP} << 'WORKEREOF'
# Set hostname
hostnamectl set-hostname ${WORKER_NAME}

# Update system
apt-get update
apt-get upgrade -y

# Install K3s agent connecting to master's private IP
curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_PRIVATE_IP}:6443 K3S_TOKEN=${K3S_TOKEN} sh -s - agent \
    --node-ip ${WORKER_PRIVATE_IP} \
    --flannel-iface eth1

# Wait for service to start
sleep 10
systemctl status k3s-agent
WORKEREOF
EOF

echo
echo "=== Worker node setup complete ==="
echo "Worker Private IP: ${WORKER_PRIVATE_IP}"
echo "Note: This node has no public IP and is only accessible via the private network"
echo
echo "Verify on master node:"
echo "ssh root@${MASTER_IP} kubectl get nodes"
echo
echo "Label the new node:"
echo "ssh root@${MASTER_IP} kubectl label node ${WORKER_NAME} node-role.kubernetes.io/worker=true"
echo "ssh root@${MASTER_IP} kubectl label node ${WORKER_NAME} workload=preferred"