#!/bin/bash

# Deploy monitoring stack with single OAuth to server

set -e

SERVER_IP="5.78.125.172"
SERVER_USER="root"

echo "=== Deploying Monitoring Stack with Single OAuth to $SERVER_IP ==="

# Check if .env exists
if [ ! -f .env ]; then
    echo "Error: .env not found. Run ./setup-single-oauth.sh first."
    exit 1
fi

# Create monitoring directory on server
echo "Creating monitoring directory on server..."
ssh $SERVER_USER@$SERVER_IP "mkdir -p /opt/monitoring/{prometheus/rules,grafana/provisioning/{datasources,dashboards},alertmanager,oauth2-proxy,exporters/blackbox}"

# Copy files to server
echo "Copying monitoring files to server..."
scp -r ./* $SERVER_USER@$SERVER_IP:/opt/monitoring/

# Copy nginx configuration
echo "Copying nginx configuration..."
scp ./nginx-monitoring-single.conf $SERVER_USER@$SERVER_IP:/tmp/

# Setup SSL certificates
echo ""
echo "Setting up SSL certificates..."
ssh $SERVER_USER@$SERVER_IP << 'EOF'
# Install certbot if not present
if ! command -v certbot &> /dev/null; then
    apt-get update
    apt-get install -y certbot python3-certbot-nginx
fi

# Get certificates for monitoring domains (if not already present)
certbot certonly --nginx -d monitoring.gmac.io --non-interactive --agree-tos --email graham.mackie@gmail.com || true
certbot certonly --nginx -d metrics.gmac.io --non-interactive --agree-tos --email graham.mackie@gmail.com || true
certbot certonly --nginx -d alerts.gmac.io --non-interactive --agree-tos --email graham.mackie@gmail.com || true

# Update main gmac.io nginx config to include OAuth2 endpoints
# This assumes you have a gmac.io config - we'll add the OAuth2 location blocks
echo "Adding OAuth2 endpoints to gmac.io nginx config..."

# Add nginx configuration for monitoring domains
cp /tmp/nginx-monitoring-single.conf /etc/nginx/sites-available/monitoring
ln -sf /etc/nginx/sites-available/monitoring /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
EOF

# Start monitoring stack
echo ""
echo "Starting monitoring stack with single OAuth..."
ssh $SERVER_USER@$SERVER_IP << 'EOF'
cd /opt/monitoring
# Use the single OAuth compose file
docker-compose -f docker-compose-single-oauth.yml down || true
docker-compose -f docker-compose-single-oauth.yml up -d
EOF

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Single sign-on monitoring services available at:"
echo "  - https://monitoring.gmac.io (Prometheus)"
echo "  - https://metrics.gmac.io (Grafana)"
echo "  - https://alerts.gmac.io (Alertmanager)"
echo ""
echo "Authentication:"
echo "  - Login once at any service"
echo "  - Cookie valid across all *.gmac.io domains"
echo "  - Only your GitHub user (gmackie) has access"
echo ""
echo "To check status:"
echo "  ssh $SERVER_USER@$SERVER_IP 'cd /opt/monitoring && docker-compose -f docker-compose-single-oauth.yml ps'"