#!/bin/bash

# Deploy monitoring stack to server

set -e

SERVER_IP="5.78.92.8"
SERVER_USER="root"

echo "=== Deploying Monitoring Stack to $SERVER_IP ==="

# Check if .env exists
if [ ! -f monitoring/.env ]; then
    echo "Error: monitoring/.env not found. Run ./setup-oauth-monitoring.sh first."
    exit 1
fi

# Create monitoring directory on server
echo "Creating monitoring directory on server..."
ssh $SERVER_USER@$SERVER_IP "mkdir -p /opt/monitoring/{prometheus/rules,grafana/provisioning/{datasources,dashboards},alertmanager,oauth2-proxy,exporters/blackbox}"

# Copy files to server
echo "Copying monitoring files to server..."
scp -r monitoring/* $SERVER_USER@$SERVER_IP:/opt/monitoring/

# Copy nginx configuration
echo "Copying nginx configuration..."
scp monitoring/nginx-monitoring.conf $SERVER_USER@$SERVER_IP:/tmp/

# Setup SSL certificates
echo ""
echo "Setting up SSL certificates..."
ssh $SERVER_USER@$SERVER_IP << 'EOF'
# Install certbot if not present
if ! command -v certbot &> /dev/null; then
    apt-get update
    apt-get install -y certbot python3-certbot-nginx
fi

# Get certificates for monitoring domains
certbot certonly --nginx -d monitoring.gmac.io --non-interactive --agree-tos --email graham.mackie@gmail.com || true
certbot certonly --nginx -d metrics.gmac.io --non-interactive --agree-tos --email graham.mackie@gmail.com || true
certbot certonly --nginx -d alerts.gmac.io --non-interactive --agree-tos --email graham.mackie@gmail.com || true

# Add nginx configuration
cp /tmp/nginx-monitoring.conf /etc/nginx/sites-available/monitoring
ln -sf /etc/nginx/sites-available/monitoring /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
EOF

# Start monitoring stack
echo ""
echo "Starting monitoring stack..."
ssh $SERVER_USER@$SERVER_IP << 'EOF'
cd /opt/monitoring
# Use the OAuth-enabled compose file
docker-compose -f docker-compose-oauth.yml down || true
docker-compose -f docker-compose-oauth.yml up -d
EOF

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Monitoring services will be available at:"
echo "  - https://monitoring.gmac.io (Prometheus)"
echo "  - https://metrics.gmac.io (Grafana)"
echo "  - https://alerts.gmac.io (Alertmanager)"
echo ""
echo "All services are protected by GitHub OAuth."
echo "Only your GitHub user (gmackie) has access."
echo ""
echo "To check status:"
echo "  ssh $SERVER_USER@$SERVER_IP 'cd /opt/monitoring && docker-compose -f docker-compose-oauth.yml ps'"