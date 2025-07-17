#!/bin/bash

# Optimize Gitea for 2GB RAM (CPX11)

# 1. Use SQLite instead of PostgreSQL
cat > docker-compose-minimal.yml << 'EOF'
version: '3'

services:
  gitea:
    image: gitea/gitea:1.21.3
    container_name: gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=sqlite3  # Less RAM usage
      - GITEA__server__OFFLINE_MODE=true  # Reduce external calls
      - GITEA__actions__ENABLED=true
      - GITEA__cache__ADAPTER=memory
      - GITEA__cache__INTERVAL=60
      - GITEA__cache__HOST=  # Use in-memory cache
    restart: always
    volumes:
      - ./gitea:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "3000:3000"
      - "222:22"
    # Limit memory usage
    mem_limit: 1g
    memswap_limit: 1g

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
      - GITEA_RUNNER_REGISTRATION_TOKEN=${RUNNER_TOKEN}
    # Limit runner memory
    mem_limit: 512m
    memswap_limit: 512m
EOF

# 2. Add swap space (important for CPX11)
cat > setup-swap.sh << 'EOF'
#!/bin/bash
# Create 2GB swap file
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Optimize swappiness for web server
echo 'vm.swappiness=10' >> /etc/sysctl.conf
sysctl -p
EOF

# 3. Limit concurrent CI jobs
cat > runner-config.yaml << 'EOF'
runner:
  capacity: 1  # Only 1 job at a time
  timeout: 30m
  
cache:
  enabled: false  # Disable cache to save RAM

container:
  options: "--memory=1g --memory-swap=1g"
EOF

# 4. Nginx caching to reduce Gitea load
cat > nginx-cache.conf << 'EOF'
# Cache static assets
location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
    proxy_pass http://localhost:3000;
}

# Cache git operations
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=git_cache:10m inactive=60m;

location ~ ^.*/(info/refs|git-upload-pack)$ {
    proxy_cache git_cache;
    proxy_cache_valid 200 5m;
    proxy_pass http://localhost:3000;
}
EOF

echo "CPX11 optimizations configured!"