#!/bin/bash
set -euo pipefail

export KUBECONFIG=~/.kube/config-hetzner
DOMAIN="gmac.io"

echo "Setting up SSO for Harbor and Gitea..."

# Get GitHub OAuth credentials
GITHUB_CLIENT_ID=$(kubectl get secret oauth2-proxy-secret -n auth-system -o jsonpath='{.data.client-id}' | base64 -d)
GITHUB_CLIENT_SECRET=$(kubectl get secret oauth2-proxy-secret -n auth-system -o jsonpath='{.data.client-secret}' | base64 -d)
COOKIE_SECRET=$(kubectl get secret oauth2-proxy-secret -n auth-system -o jsonpath='{.data.cookie-secret}' | base64 -d)

echo "=== Configuring Gitea for GitHub OAuth ==="

# First, we need to configure Gitea through its API
# Get Gitea admin credentials
GITEA_ADMIN_USER="gitea_admin"
GITEA_ADMIN_PASSWORD="F5NOhF7cgQ5GU4vVFo2aWA77j"

# Port-forward to Gitea to access its API
echo "Setting up port-forward to Gitea..."
kubectl port-forward -n gitea svc/gitea-http 3000:3000 &
PF_PID=$!
sleep 5

# Create OAuth2 application in Gitea for GitHub
echo "Configuring Gitea OAuth2 settings..."

# First, let's create the GitHub OAuth source via Gitea's UI API
# This requires accessing Gitea's admin panel

# Create a config file for Gitea OAuth
cat > /tmp/gitea-oauth-config.json <<EOF
{
  "name": "GitHub",
  "provider": "github",
  "client_id": "${GITHUB_CLIENT_ID}",
  "client_secret": "${GITHUB_CLIENT_SECRET}",
  "auto_discover_url": "",
  "use_custom_urls": false,
  "custom_auth_url": "",
  "custom_token_url": "",
  "custom_profile_url": "",
  "custom_email_url": "",
  "icon_url": "",
  "skip_local_2fa": true,
  "scopes": ["user:email", "read:org"],
  "required_claim_name": "",
  "required_claim_value": "",
  "group_claim_name": "",
  "admin_group": "",
  "restricted_group": "",
  "group_team_map": "",
  "group_team_map_removal": false
}
EOF

echo ""
echo "=== Manual Configuration Required ==="
echo ""
echo "Please complete the following manual steps:"
echo ""
echo "1. GITEA GitHub OAuth Setup:"
echo "   - Go to https://git.gmac.io/admin/auths/new"
echo "   - Login with: username='${GITEA_ADMIN_USER}' password='${GITEA_ADMIN_PASSWORD}'"
echo "   - Choose 'OAuth2' as Authentication Type"
echo "   - Choose 'GitHub' as OAuth2 Provider"
echo "   - Set OAuth2 Client ID: ${GITHUB_CLIENT_ID}"
echo "   - Set OAuth2 Client Secret: ${GITHUB_CLIENT_SECRET}"
echo "   - Enable 'Enable Auto Registration'"
echo "   - Click 'Add Authentication Source'"
echo ""
echo "2. For HARBOR:"
echo "   Harbor will continue to use oauth2-proxy protection at the ingress level."
echo "   This provides GitHub SSO for the web UI automatically."
echo "   For CLI/API access, use Harbor local accounts."
echo ""
echo "3. Update your GitHub OAuth App (if needed):"
echo "   - Add https://git.gmac.io/user/oauth2/GitHub/callback to redirect URIs"
echo ""

# Kill the port-forward
kill $PF_PID 2>/dev/null || true

# Clean up
rm -f /tmp/gitea-oauth-config.json

echo "Configuration prepared. Please follow the manual steps above."