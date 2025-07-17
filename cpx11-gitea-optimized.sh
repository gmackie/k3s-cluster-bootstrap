#!/bin/bash

# Optimized Gitea setup for CPX11 (2GB RAM)

# Deploy CPX11 server
cat > deploy-cpx11.sh << 'EOF'
#!/bin/bash

# Create the server
hcloud server create \
    --name gitea-ci \
    --type cpx11 \
    --image ubuntu-22.04 \
    --location ash \
    --ssh-key ~/.ssh/id_ed25519.pub

IP=$(hcloud server ip gitea-ci)
echo "Server IP: $IP"
sleep 30

# Configure server
ssh root@$IP 'bash -s' << 'SETUP'
# Add swap (critical for 2GB RAM)
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo 'vm.swappiness=10' >> /etc/sysctl.conf
sysctl -p

# Install Docker
curl -fsSL https://get.docker.com | sh

# Optimize Docker for low memory
cat > /etc/docker/daemon.json << JSON
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
JSON

systemctl restart docker
SETUP
EOF

# Minimal Gitea stack
cat > docker-compose-minimal.yml << 'EOF'
version: '3'

services:
  gitea:
    image: gitea/gitea:1.21.3
    container_name: gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=sqlite3  # Uses ~50MB vs 200MB+ for PostgreSQL
      - GITEA__server__OFFLINE_MODE=true
      - GITEA__server__DISABLE_ROUTER_LOG=true
      - GITEA__actions__ENABLED=true
      - GITEA__cache__ENABLED=false  # Save memory
      - GITEA__indexer__REPO_INDEXER_ENABLED=false  # Save memory
    restart: always
    volumes:
      - ./gitea:/data
    ports:
      - "3000:3000"
      - "222:22"
    deploy:
      resources:
        limits:
          memory: 1200M  # Leave 800MB for system + runner

  # Single lightweight runner
  runner:
    image: gitea/act_runner:latest
    container_name: gitea_runner
    restart: always
    depends_on:
      - gitea
    volumes:
      - ./runner:/data
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - GITEA_INSTANCE_URL=http://gitea:3000
      - GITEA_RUNNER_NAME=cpx11-runner
      - GITEA_RUNNER_CAPACITY=1  # Only 1 concurrent job
    deploy:
      resources:
        limits:
          memory: 512M
EOF

# Performance tuning script
cat > tune-performance.sh << 'EOF'
#!/bin/bash

# 1. Limit Gitea resource usage
docker update --memory="1200m" --memory-swap="2g" gitea
docker update --memory="512m" --memory-swap="1g" gitea_runner

# 2. Configure single job runner
mkdir -p runner
cat > runner/config.yaml << CONFIG
runner:
  capacity: 1  # Critical: only 1 job at a time
  timeout: 30m

cache:
  enabled: false  # Disable caching

container:
  network: bridge
  options: "--memory=1g --memory-swap=2g"
  valid_volumes: []
CONFIG

# 3. Add cleanup cron
echo "0 */6 * * * docker system prune -af --filter until=6h" | crontab -

echo "CPX11 optimized for Gitea!"
EOF
EOF