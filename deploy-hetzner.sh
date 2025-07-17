#!/bin/bash

# Deploy Gitea on Hetzner Cloud

# Install hcloud CLI (on your local machine)
# brew install hcloud  # macOS
# or download from https://github.com/hetznercloud/cli

# Create SSH key if you don't have one
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "gitea-ci"
fi

# Login to Hetzner
hcloud context create gitea-ci

# Create the server
hcloud server create \
    --name gitea-ci \
    --type cx21 \
    --image ubuntu-22.04 \
    --location ash \
    --ssh-key ~/.ssh/id_ed25519.pub

# Get the IP
IP=$(hcloud server ip gitea-ci)
echo "Server IP: $IP"

# Wait for server to be ready
sleep 30

# Copy setup script and run
scp setup-gitea-ci.sh root@$IP:/root/
scp docker-compose.yml root@$IP:/root/

ssh root@$IP << 'EOF'
# Run setup
chmod +x setup-gitea-ci.sh
./setup-gitea-ci.sh

# Or use Docker Compose
apt update && apt install -y docker.io docker-compose
docker-compose up -d
EOF

echo "Gitea is installing at: http://$IP:3000"
echo "Add this IP to Route 53: $IP"