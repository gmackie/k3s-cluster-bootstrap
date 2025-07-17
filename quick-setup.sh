#!/bin/bash

# Quick Gitea setup for ci.gmac.io

echo "=== Gitea Setup for ci.gmac.io ==="
echo "Server IP: 5.78.92.8"
echo "Domain: ci.gmac.io"

# SSH into your server and run:
cat << 'SSH_COMMANDS'

# 1. Update system
apt update && apt upgrade -y

# 2. Install Docker
curl -fsSL https://get.docker.com | sh

# 3. Add swap (important for CPX11)
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 4. Create Gitea directory
mkdir -p /opt/gitea && cd /opt/gitea

# 5. Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3'

services:
  gitea:
    image: gitea/gitea:1.21.3
    container_name: gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=sqlite3
      - GITEA__server__DOMAIN=ci.gmac.io
      - GITEA__server__ROOT_URL=https://ci.gmac.io/
      - GITEA__server__HTTP_PORT=3000
      - GITEA__actions__ENABLED=true
    restart: always
    volumes:
      - ./gitea:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "3000:3000"
      - "222:22"

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
      - GITEA_RUNNER_NAME=ci-gmac-io-runner
EOF

# 6. Start Gitea
docker-compose up -d

# 7. Install Nginx & Certbot
apt install -y nginx certbot python3-certbot-nginx

# 8. Configure Nginx
cat > /etc/nginx/sites-available/gitea << 'NGINX'
server {
    listen 80;
    server_name ci.gmac.io;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 500M;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/gitea /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# 9. Get SSL certificate
certbot --nginx -d ci.gmac.io --non-interactive --agree-tos -m your-email@example.com

echo "====================================="
echo "Gitea is ready!"
echo "Visit: https://ci.gmac.io"
echo "====================================="

SSH_COMMANDS