#!/bin/bash

# Gitea + Gitea Actions Setup Script
# For Ubuntu 22.04 LTS

set -e

# Variables
DOMAIN="ci.yourdomain.com"
GITEA_VERSION="1.21.3"
RUNNER_VERSION="0.2.6"

# Update system
apt update && apt upgrade -y
apt install -y docker.io docker-compose nginx certbot python3-certbot-nginx

# Create gitea user
adduser --system --shell /bin/bash --gecos 'Git Version Control' --group --disabled-password --home /home/git git

# Install Gitea
wget -O gitea https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64
chmod +x gitea
mv gitea /usr/local/bin/gitea

# Create directories
mkdir -p /var/lib/gitea/{custom,data,log}
chown -R git:git /var/lib/gitea/
chmod -R 750 /var/lib/gitea/
mkdir /etc/gitea
chown root:git /etc/gitea
chmod 770 /etc/gitea

# Create systemd service
cat > /etc/systemd/system/gitea.service <<EOF
[Unit]
Description=Gitea
After=syslog.target
After=network.target

[Service]
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea/
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Create initial config
cat > /etc/gitea/app.ini <<EOF
[server]
DOMAIN = ${DOMAIN}
ROOT_URL = https://${DOMAIN}/
HTTP_PORT = 3000
DISABLE_SSH = false
SSH_PORT = 22

[database]
DB_TYPE = sqlite3
PATH = /var/lib/gitea/data/gitea.db

[repository]
ROOT = /var/lib/gitea/data/gitea-repositories

[security]
INSTALL_LOCK = false
SECRET_KEY = 

[service]
DISABLE_REGISTRATION = false
REQUIRE_SIGNIN_VIEW = false

[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = https://gitea.com
EOF

chown root:git /etc/gitea/app.ini
chmod 640 /etc/gitea/app.ini

# Setup Nginx
cat > /etc/nginx/sites-available/gitea <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -s /etc/nginx/sites-available/gitea /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# Start Gitea
systemctl enable gitea
systemctl start gitea

echo "Gitea installed! Visit http://${DOMAIN} to complete setup"
echo "After setup, run: certbot --nginx -d ${DOMAIN}"

# Setup Act Runner after Gitea is configured
cat > /usr/local/bin/setup-runner.sh <<'RUNNER_SCRIPT'
#!/bin/bash

# Download act_runner
wget -O act_runner https://dl.gitea.com/act_runner/${RUNNER_VERSION}/act_runner-${RUNNER_VERSION}-linux-amd64
chmod +x act_runner
mv act_runner /usr/local/bin/

# Create runner directory
mkdir -p /var/lib/gitea-runner
cd /var/lib/gitea-runner

# Register runner (you'll need to get token from Gitea UI)
echo "Get runner token from Gitea: Settings -> Actions -> Runners"
read -p "Enter runner registration token: " TOKEN

act_runner register \
  --no-interactive \
  --instance https://${DOMAIN} \
  --token $TOKEN \
  --name "runner-1" \
  --labels "ubuntu-latest:docker://node:18-bullseye"

# Create systemd service for runner
cat > /etc/systemd/system/gitea-runner.service <<EOF
[Unit]
Description=Gitea Actions runner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/gitea-runner
ExecStart=/usr/local/bin/act_runner daemon
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable gitea-runner
systemctl start gitea-runner
RUNNER_SCRIPT

chmod +x /usr/local/bin/setup-runner.sh
echo "Run 'setup-runner.sh' after configuring Gitea!"