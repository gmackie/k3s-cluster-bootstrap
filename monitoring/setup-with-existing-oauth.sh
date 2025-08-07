#!/bin/bash

# Setup monitoring with existing OAuth app

set -e

echo "=== Setting up Monitoring with Existing OAuth App ==="
echo ""

# Source the existing credentials
source ../.env

# Generate cookie secret
COOKIE_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Grafana password
GRAFANA_PASSWORD=$(openssl rand -base64 12)

# Create monitoring .env file using existing OAuth credentials
cat > .env << EOF
# Using existing GitHub OAuth App
GITHUB_CLIENT_ID=$K3S_GITHUB_OAUTH_CLIENT_ID
GITHUB_CLIENT_SECRET=$K3S_GITHUB_OAUTH_CLIENT_SECRET
COOKIE_SECRET=$COOKIE_SECRET

# Grafana admin credentials (for initial setup)
GRAFANA_USER=admin
GRAFANA_PASSWORD=$GRAFANA_PASSWORD
EOF

chmod 600 .env

echo "✓ OAuth configuration created using existing app credentials"
echo ""
echo "OAuth App Details:"
echo "  - Client ID: $K3S_GITHUB_OAUTH_CLIENT_ID"
echo "  - Callback URL: https://gmac.io/oauth2/callback"
echo "  - Scope: user:email read:org"
echo ""
echo "Generated Credentials:"
echo "  - Cookie Secret: [generated]"
echo "  - Grafana Admin Password: $GRAFANA_PASSWORD"
echo ""
echo "Next step: ./deploy-single-oauth.sh"