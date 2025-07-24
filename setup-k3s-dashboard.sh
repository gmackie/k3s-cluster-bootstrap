#!/bin/bash
# Automated setup script for K3s Dashboard with GitHub SSO
# Configured specifically for gmackie GitHub user access only

set -e

echo "=== K3s Dashboard Automated Setup ==="
echo "Setting up Kubernetes Dashboard with GitHub OAuth2 SSO"
echo "Access restricted to: gmackie"
echo

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not available. Please install k3s first."
    exit 1
fi

# Check if k3s is running
if ! kubectl get nodes &> /dev/null; then
    echo "Error: Cannot connect to k3s cluster. Please check your kubeconfig."
    exit 1
fi

echo "✅ K3s cluster is accessible"

# Load environment variables from .env file
if [ -f .env ]; then
    source .env
    echo "✅ Loaded environment variables from .env"
else
    echo "❌ .env file not found!"
    echo "Please create a .env file with:"
    echo "export K3S_GITHUB_OAUTH_CLIENT_ID=your_client_id"
    echo "export K3S_GITHUB_OAUTH_CLIENT_SECRET=your_client_secret"
    exit 1
fi

# GitHub OAuth App Configuration from environment
GITHUB_CLIENT_ID="$K3S_GITHUB_OAUTH_CLIENT_ID"
GITHUB_CLIENT_SECRET="$K3S_GITHUB_OAUTH_CLIENT_SECRET"

# Check if GitHub OAuth credentials are set
if [ -z "$GITHUB_CLIENT_ID" ] || [ -z "$GITHUB_CLIENT_SECRET" ]; then
    echo "❌ GitHub OAuth credentials not found in .env file!"
    echo "Please ensure your .env file contains:"
    echo "export K3S_GITHUB_OAUTH_CLIENT_ID=your_client_id"
    echo "export K3S_GITHUB_OAUTH_CLIENT_SECRET=your_client_secret"
    exit 1
fi

# Function to generate random string for cookie secret
generate_cookie_secret() {
    python3 -c "import secrets; print(secrets.token_urlsafe(32))"
}

# Generate cookie secret
COOKIE_SECRET=$(generate_cookie_secret)
echo "✅ Generated secure cookie secret"

echo
echo "=== Deploying Dashboard ==="

# Create the secrets first
kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -

# Create OAuth2 proxy secrets
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: oauth2-proxy-secrets
  namespace: kubernetes-dashboard
type: Opaque
stringData:
  client-id: "$GITHUB_CLIENT_ID"
  client-secret: "$GITHUB_CLIENT_SECRET"
  cookie-secret: "$COOKIE_SECRET"
EOF

echo "✅ OAuth2 secrets created"

# Apply the main dashboard configuration
kubectl apply -f k3s-dashboard-setup.yaml

echo "✅ Dashboard configuration applied"

# Wait for deployments to be ready
echo "Waiting for deployments to be ready..."
echo "This may take a few minutes for images to download..."

# Wait for namespace to be ready
kubectl wait --for=condition=Ready pods --all -n kubernetes-dashboard --timeout=600s || true

# Check deployment status
echo
echo "=== Deployment Status ==="
kubectl get deployments -n kubernetes-dashboard
kubectl get pods -n kubernetes-dashboard
kubectl get ingress -n kubernetes-dashboard

# Get admin token for emergency access
echo
echo "=== Admin Token (Emergency Access) ==="
echo "Save this token for emergency dashboard access:"
kubectl -n kubernetes-dashboard create token admin-user --duration=8760h || echo "Admin token will be available once deployment is ready"

echo
echo "=== Setup Complete ==="
echo
echo "✅ Dashboard deployed successfully!"
echo "✅ Access restricted to GitHub user: gmackie"
echo "✅ HTTPS enabled with Let's Encrypt"
echo
echo "Next steps:"
echo "1. Ensure DNS points k3s.gmac.io to 5.78.92.8"
echo "2. Wait for Let's Encrypt certificate (check with: kubectl get certificate -n kubernetes-dashboard)"
echo "3. Access dashboard at: https://k3s.gmac.io"
echo
echo "Monitoring commands:"
echo "kubectl get certificate k3s-dashboard-tls -n kubernetes-dashboard"
echo "kubectl logs -f deployment/oauth2-proxy -n kubernetes-dashboard"
echo "kubectl logs -f deployment/kubernetes-dashboard -n kubernetes-dashboard"
echo
echo "Only the GitHub user 'gmackie' will be able to access the dashboard."