#!/bin/bash
set -euo pipefail

# Hetzner Cloud CLI script to create and add a worker node

echo "=== Hetzner K3s Worker Node Setup ==="
echo

# Check for hcloud CLI
if ! command -v hcloud &> /dev/null; then
    echo "Error: hcloud CLI not found. Install it first:"
    echo "brew install hcloud"
    exit 1
fi

# Configuration
WORKER_NAME=${1:-k3s-worker-1}
SERVER_TYPE=${2:-cx31}  # 2 vCPU, 8GB RAM, 80GB SSD
LOCATION="fsn1"
IMAGE="ubuntu-24.04"
MASTER_IP="5.78.106.236"

echo "Creating worker node:"
echo "  Name: ${WORKER_NAME}"
echo "  Type: ${SERVER_TYPE}"
echo "  Location: ${LOCATION}"
echo

# Create the server
echo "Creating Hetzner server..."
hcloud server create \
    --name "${WORKER_NAME}" \
    --type "${SERVER_TYPE}" \
    --image "${IMAGE}" \
    --location "${LOCATION}" \
    --ssh-key k3s-cluster-key \
    --label purpose=k3s-worker

# Get the new server's IP
WORKER_IP=$(hcloud server ip "${WORKER_NAME}")
echo "Worker node created with IP: ${WORKER_IP}"

# Wait for SSH to be ready
echo "Waiting for SSH to be ready..."
sleep 30
while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@${WORKER_IP} echo "SSH ready" 2>/dev/null; do
    echo -n "."
    sleep 5
done
echo

# Get K3s token from master
echo "Getting K3s token from master..."
K3S_TOKEN=$(ssh root@${MASTER_IP} "cat /var/lib/rancher/k3s/server/node-token")

# Setup worker node
echo "Setting up worker node..."
ssh root@${WORKER_IP} << EOF
# Set hostname
hostnamectl set-hostname ${WORKER_NAME}

# Update system
apt-get update
apt-get upgrade -y

# Install K3s agent
curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${K3S_TOKEN} sh -s - agent

# Wait for service to start
sleep 10
systemctl status k3s-agent
EOF

echo
echo "=== Worker node setup complete ==="
echo "Worker IP: ${WORKER_IP}"
echo
echo "Verify on master node:"
echo "kubectl get nodes"
echo
echo "Label the new node:"
echo "kubectl label node ${WORKER_NAME} node-role.kubernetes.io/worker=true"
echo "kubectl label node ${WORKER_NAME} workload=preferred"