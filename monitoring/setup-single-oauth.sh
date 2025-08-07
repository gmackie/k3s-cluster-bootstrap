#!/bin/bash

# Setup single OAuth2 app for all monitoring services

set -e

echo "=== Setting up Single OAuth2 App for Monitoring Services ==="
echo ""
echo "You need to create 1 GitHub OAuth App:"
echo ""
echo "GitHub OAuth App Settings:"
echo "  - Application name: GMAC.IO Monitoring"
echo "  - Homepage URL: https://gmac.io"
echo "  - Authorization callback URL: https://gmac.io/oauth2/callback"
echo ""
echo "Create this at: https://github.com/settings/developers"
echo ""
read -p "Press enter when you've created the OAuth app..."

# Create .env file
echo ""
echo "Enter the OAuth app credentials:"
echo ""

read -p "GitHub Client ID: " GITHUB_CLIENT_ID
read -sp "GitHub Client Secret: " GITHUB_CLIENT_SECRET
echo ""

# Generate cookie secret
COOKIE_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Grafana password
GRAFANA_PASSWORD=$(openssl rand -base64 12)

# Create .env file
cat > monitoring/.env << EOF
# Single GitHub OAuth App
GITHUB_CLIENT_ID=$GITHUB_CLIENT_ID
GITHUB_CLIENT_SECRET=$GITHUB_CLIENT_SECRET
COOKIE_SECRET=$COOKIE_SECRET

# Grafana admin credentials (for initial setup)
GRAFANA_USER=admin
GRAFANA_PASSWORD=$GRAFANA_PASSWORD
EOF

chmod 600 monitoring/.env

echo ""
echo "OAuth configuration saved to monitoring/.env"
echo ""
echo "Benefits of this setup:"
echo "- Single OAuth app to manage"
echo "- Single sign-on across all monitoring services"
echo "- Cookie shared across all *.gmac.io subdomains"
echo "- Authenticate once, access all services"
echo ""
echo "Next steps:"
echo "1. Deploy to server: ./deploy-single-oauth.sh"
echo "2. Services will be available at:"
echo "   - https://monitoring.gmac.io (Prometheus)"
echo "   - https://metrics.gmac.io (Grafana)"
echo "   - https://alerts.gmac.io (Alertmanager)"
echo ""
echo "Note: After authenticating at any service, you'll be logged into all of them!"