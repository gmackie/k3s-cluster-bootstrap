#!/bin/bash

# Setup OAuth2 for monitoring services

set -e

echo "=== Setting up OAuth2 for Monitoring Services ==="
echo ""
echo "You need to create 3 GitHub OAuth Apps:"
echo ""
echo "1. Prometheus (monitoring.gmac.io):"
echo "   - Application name: GMAC.IO Prometheus"
echo "   - Homepage URL: https://monitoring.gmac.io"
echo "   - Authorization callback URL: https://monitoring.gmac.io/oauth2/callback"
echo ""
echo "2. Grafana (metrics.gmac.io):"
echo "   - Application name: GMAC.IO Grafana"
echo "   - Homepage URL: https://metrics.gmac.io"
echo "   - Authorization callback URL: https://metrics.gmac.io/oauth2/callback"
echo ""
echo "3. Alertmanager (alerts.gmac.io):"
echo "   - Application name: GMAC.IO Alertmanager"
echo "   - Homepage URL: https://alerts.gmac.io"
echo "   - Authorization callback URL: https://alerts.gmac.io/oauth2/callback"
echo ""
echo "Create these at: https://github.com/settings/developers"
echo ""
read -p "Press enter when you've created all 3 OAuth apps..."

# Create .env file
echo ""
echo "Enter the OAuth app credentials:"
echo ""

# Prometheus
read -p "Prometheus Client ID: " PROMETHEUS_CLIENT_ID
read -sp "Prometheus Client Secret: " PROMETHEUS_CLIENT_SECRET
echo ""

# Grafana
read -p "Grafana Client ID: " GRAFANA_CLIENT_ID
read -sp "Grafana Client Secret: " GRAFANA_CLIENT_SECRET
echo ""

# Alertmanager
read -p "Alertmanager Client ID: " ALERTMANAGER_CLIENT_ID
read -sp "Alertmanager Client Secret: " ALERTMANAGER_CLIENT_SECRET
echo ""

# Generate cookie secrets
COOKIE_SECRET_PROMETHEUS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
COOKIE_SECRET_GRAFANA=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
COOKIE_SECRET_ALERTMANAGER=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Create .env file
cat > monitoring/.env << EOF
# GitHub OAuth for Prometheus
GITHUB_CLIENT_ID_PROMETHEUS=$PROMETHEUS_CLIENT_ID
GITHUB_CLIENT_SECRET_PROMETHEUS=$PROMETHEUS_CLIENT_SECRET
COOKIE_SECRET_PROMETHEUS=$COOKIE_SECRET_PROMETHEUS

# GitHub OAuth for Grafana
GITHUB_CLIENT_ID_GRAFANA=$GRAFANA_CLIENT_ID
GITHUB_CLIENT_SECRET_GRAFANA=$GRAFANA_CLIENT_SECRET
COOKIE_SECRET_GRAFANA=$COOKIE_SECRET_GRAFANA

# GitHub OAuth for Alertmanager
GITHUB_CLIENT_ID_ALERTMANAGER=$ALERTMANAGER_CLIENT_ID
GITHUB_CLIENT_SECRET_ALERTMANAGER=$ALERTMANAGER_CLIENT_SECRET
COOKIE_SECRET_ALERTMANAGER=$COOKIE_SECRET_ALERTMANAGER

# Grafana admin credentials (for initial setup)
GRAFANA_USER=admin
GRAFANA_PASSWORD=$(openssl rand -base64 12)
EOF

chmod 600 monitoring/.env

echo ""
echo "OAuth configuration saved to monitoring/.env"
echo ""
echo "Next steps:"
echo "1. Deploy to server: ./deploy-monitoring.sh"
echo "2. Configure SSL certificates on server"
echo "3. Add nginx configuration"
echo "4. Access services at:"
echo "   - https://monitoring.gmac.io (Prometheus)"
echo "   - https://metrics.gmac.io (Grafana)"
echo "   - https://alerts.gmac.io (Alertmanager)"