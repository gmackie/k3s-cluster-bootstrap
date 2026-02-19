#!/bin/bash
set -euo pipefail

export KUBECONFIG=~/.kube/config-hetzner
SEALED_SECRETS_VERSION="v0.26.1"

echo "Installing Sealed Secrets controller..."

# Create namespace
kubectl create namespace sealed-secrets --dry-run=client -o yaml | kubectl apply -f -

# Install Sealed Secrets controller
echo "Deploying Sealed Secrets controller ${SEALED_SECRETS_VERSION}..."
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml

# Wait for controller to be ready
echo "Waiting for Sealed Secrets controller to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/sealed-secrets-controller -n sealed-secrets

# Get the public key
echo "Retrieving public key..."
mkdir -p .cluster
kubectl get secret -n sealed-secrets sealed-secrets-key -o jsonpath='{.data.tls\.crt}' | base64 -d > .cluster/sealed-secrets-public.pem

# Install kubeseal CLI
if ! command -v kubeseal >/dev/null 2>&1; then
    echo "Installing kubeseal CLI..."
    KUBESEAL_VERSION=$(echo $SEALED_SECRETS_VERSION | sed 's/v//')
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/kubeseal-${KUBESEAL_VERSION}-darwin-amd64.tar.gz | tar xz
        chmod +x kubeseal
        sudo mv kubeseal /usr/local/bin/
    else
        # Linux
        curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz | tar xz
        chmod +x kubeseal
        sudo mv kubeseal /usr/local/bin/
    fi
fi

echo "Sealed Secrets installed successfully!"
echo ""
echo "Public key saved to: .cluster/sealed-secrets-public.pem"
echo ""
echo "Example: Create a sealed secret for npm registry CI:"
echo "kubectl create secret generic npm-registry-ci \\"
echo "  --from-literal=NPM_TOKEN=\$(echo -n 'ci-build:WE05dmseLgMTy2qa' | base64) \\"
echo "  --dry-run=client -o yaml | kubeseal -o yaml > npm-registry-ci-sealed.yaml"