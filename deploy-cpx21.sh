#!/bin/bash

# Deploy Gitea on Hetzner CPX21

# Create server with CPX21
hcloud server create \
    --name gitea-ci \
    --type cpx21 \
    --image ubuntu-22.04 \
    --location ash \
    --ssh-key ~/.ssh/id_ed25519.pub

# Get IP
IP=$(hcloud server ip gitea-ci)
echo "Server created at: $IP"

# Quick setup via SSH
ssh root@$IP << 'EOF'
# Install Docker
curl -fsSL https://get.docker.com | sh

# Create docker-compose.yml
cat > docker-compose.yml << 'COMPOSE'
version: '3'

services:
  gitea:
    image: gitea/gitea:1.21.3
    container_name: gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=db:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=gitea
      - GITEA__actions__ENABLED=true
    restart: always
    networks:
      - gitea
    volumes:
      - ./gitea:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "3000:3000"
      - "222:22"
    depends_on:
      - db

  db:
    image: postgres:15-alpine  # Alpine uses less RAM
    restart: always
    environment:
      - POSTGRES_USER=gitea
      - POSTGRES_PASSWORD=gitea
      - POSTGRES_DB=gitea
    networks:
      - gitea
    volumes:
      - ./postgres:/var/lib/postgresql/data

  runner:
    image: gitea/act_runner:latest
    restart: always
    depends_on:
      - gitea
    volumes:
      - ./runner:/data
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - GITEA_INSTANCE_URL=http://gitea:3000
      - GITEA_RUNNER_NAME=cpx21-runner
    networks:
      - gitea

networks:
  gitea:
    external: false
COMPOSE

# Start services
docker-compose up -d

echo "Gitea starting on http://$IP:3000"
EOF