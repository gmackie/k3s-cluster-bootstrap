#!/bin/bash
set -euo pipefail

# Drone CI Component Installation
# Provides container-native CI/CD integrated with Gitea

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="drone"
COMPONENT_NAMESPACE="drone"

install_drone() {
    info "Installing Drone CI..."
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for Drone installation"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Check if Gitea is installed
    if ! kubectl get namespace gitea &>/dev/null; then
        error "Gitea must be installed before Drone CI"
        echo "Please install Gitea component first"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate secrets
    DRONE_RPC_SECRET=$(openssl rand -hex 32)
    DRONE_DATABASE_SECRET=$(generate_password)
    GITEA_CLIENT_ID=$(openssl rand -hex 16)
    GITEA_CLIENT_SECRET=$(openssl rand -hex 32)
    
    # Get Gitea admin credentials
    if [[ -f "${SCRIPT_DIR}/../../.cluster/credentials/gitea.conf" ]]; then
        source "${SCRIPT_DIR}/../../.cluster/credentials/gitea.conf"
    else
        error "Gitea credentials not found. Please ensure Gitea is properly installed."
        exit 1
    fi
    
    # Save Drone credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/drone.conf" <<EOF
DRONE_URL=https://ci.${DOMAIN}
DRONE_RPC_SECRET=$DRONE_RPC_SECRET
GITEA_CLIENT_ID=$GITEA_CLIENT_ID
GITEA_CLIENT_SECRET=$GITEA_CLIENT_SECRET
DATABASE_PASSWORD=$DRONE_DATABASE_SECRET
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/drone.conf"
    
    # Create OAuth application in Gitea
    info "Creating OAuth application in Gitea..."
    # This would normally be done via Gitea API, but for now we'll document the manual step
    
    # Create secrets
    kubectl create secret generic drone-secrets \
        --namespace=${COMPONENT_NAMESPACE} \
        --from-literal=rpc-secret="${DRONE_RPC_SECRET}" \
        --from-literal=database-password="${DRONE_DATABASE_SECRET}" \
        --from-literal=gitea-client-id="${GITEA_CLIENT_ID}" \
        --from-literal=gitea-client-secret="${GITEA_CLIENT_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy PostgreSQL for Drone
    info "Deploying PostgreSQL for Drone..."
    envsubst < "${SCRIPT_DIR}/postgres-deployment.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/postgres-service.yaml"
    
    # Wait for PostgreSQL
    kubectl wait --for=condition=ready pod -l app=drone-postgres -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Deploy Drone server
    info "Deploying Drone server..."
    envsubst < "${SCRIPT_DIR}/drone-server-deployment.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/drone-server-service.yaml"
    envsubst < "${SCRIPT_DIR}/drone-server-ingress.yaml" | kubectl apply -f -
    
    # Deploy Drone Docker runner
    info "Deploying Drone Docker runner..."
    envsubst < "${SCRIPT_DIR}/drone-runner-docker-deployment.yaml" | kubectl apply -f -
    
    # Deploy Drone Kubernetes runner
    info "Deploying Drone Kubernetes runner..."
    kubectl apply -f "${SCRIPT_DIR}/drone-runner-kube-rbac.yaml"
    envsubst < "${SCRIPT_DIR}/drone-runner-kube-deployment.yaml" | kubectl apply -f -
    
    # Wait for deployments
    info "Waiting for Drone deployments..."
    kubectl rollout status deployment/drone-server -n ${COMPONENT_NAMESPACE} --timeout=300s
    kubectl rollout status deployment/drone-runner-docker -n ${COMPONENT_NAMESPACE} --timeout=300s
    kubectl rollout status deployment/drone-runner-kube -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    success "Drone CI installed successfully!"
    
    # Display access information
    info "Drone CI Access Information:"
    echo "  URL: https://ci.${DOMAIN}"
    echo ""
    echo "IMPORTANT: Manual configuration required in Gitea:"
    echo "  1. Login to Gitea as admin: https://git.${DOMAIN}"
    echo "  2. Go to Settings -> Applications"
    echo "  3. Create new OAuth2 Application:"
    echo "     - Application Name: Drone CI"
    echo "     - Redirect URI: https://ci.${DOMAIN}/login"
    echo "  4. Copy the Client ID and Client Secret"
    echo "  5. Update Drone deployment with real OAuth credentials:"
    echo "     kubectl edit deployment drone-server -n drone"
    echo ""
    echo "Example .drone.yml for your repositories:"
    cat <<'EXAMPLE'
---
kind: pipeline
type: kubernetes
name: default

steps:
- name: test
  image: node:18
  commands:
  - npm install
  - npm test

- name: build
  image: plugins/docker
  settings:
    repo: registry.${DOMAIN}/myapp
    tags: latest
    registry: registry.${DOMAIN}
EXAMPLE
    echo ""
    echo "Credentials saved to: ${SCRIPT_DIR}/../../.cluster/credentials/drone.conf"
}

uninstall_drone() {
    info "Uninstalling Drone CI..."
    
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "Drone CI uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_drone
        ;;
    uninstall)
        uninstall_drone
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac