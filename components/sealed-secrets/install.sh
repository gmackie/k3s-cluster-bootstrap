#!/bin/bash
set -euo pipefail

# Sealed Secrets installation script
# This provides encrypted secrets that can be stored in Git

# Source common functions if not already loaded
if ! command -v info >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/common.sh"
fi

COMPONENT_NAME="sealed-secrets"
COMPONENT_NAMESPACE="sealed-secrets"
SEALED_SECRETS_VERSION="v0.26.1"

info "Installing Sealed Secrets controller..."

# Create namespace
ensure_namespace "$COMPONENT_NAMESPACE"

# Install Sealed Secrets controller using official manifest
info "Deploying Sealed Secrets controller ${SEALED_SECRETS_VERSION}..."
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml

# Wait for controller to be ready
info "Waiting for Sealed Secrets controller to be ready..."
wait_for_deployment "$COMPONENT_NAMESPACE" "sealed-secrets-controller"

# Get the public key for sealing secrets
info "Retrieving public key for sealing secrets..."
kubectl get secret -n "$COMPONENT_NAMESPACE" sealed-secrets-key -o jsonpath='{.data.tls\.crt}' | base64 -d > .cluster/sealed-secrets-public.pem

# Save component state
save_component_state "$COMPONENT_NAME" "installed"

# Install kubeseal CLI if not present
if ! command -v kubeseal >/dev/null 2>&1; then
    info "Installing kubeseal CLI..."
    KUBESEAL_VERSION=$(echo $SEALED_SECRETS_VERSION | sed 's/v//')
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/kubeseal-${KUBESEAL_VERSION}-darwin-amd64.tar.gz | tar xz
        sudo mv kubeseal /usr/local/bin/
    else
        # Linux
        curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz | tar xz
        sudo mv kubeseal /usr/local/bin/
    fi
fi

success "Sealed Secrets installed successfully!"
info "=== Sealed Secrets Information ==="
info "Controller namespace: $COMPONENT_NAMESPACE"
info "Public key saved to: .cluster/sealed-secrets-public.pem"
info ""
info "=== Usage Examples ==="
info "Create a sealed secret:"
info "  kubectl create secret generic mysecret --dry-run=client --from-literal=password=mypassword -o yaml | kubeseal -o yaml > mysealedsecret.yaml"
info ""
info "Create sealed secret with scope:"
info "  kubeseal --scope cluster-wide < secret.yaml > sealed-secret.yaml"
info ""
info "Use public key file (for CI/CD):"
info "  kubeseal --cert .cluster/sealed-secrets-public.pem < secret.yaml > sealed-secret.yaml"
info ""
info "=== Important Notes ==="
info "- Sealed secrets can be stored in Git safely"
info "- Only the cluster can decrypt sealed secrets"
info "- Back up the master key from sealed-secrets namespace"
info "- Default scope is strict (namespace + name)"