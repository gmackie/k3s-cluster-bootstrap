#!/bin/bash
set -euo pipefail

# NPM Registry Component Installation
# Installs Verdaccio as a private npm registry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="npm-registry"
COMPONENT_NAMESPACE="npm-registry"

install_npm_registry() {
    info "Installing NPM Registry (Verdaccio)..."
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Build custom Docker image with auth-proxy plugin
    info "Building custom Verdaccio image with auth-proxy plugin..."
    "${SCRIPT_DIR}/build-image.sh"
    
    # Apply Kubernetes manifests
    kubectl apply -f "${SCRIPT_DIR}/verdaccio-pvc.yaml"
    kubectl apply -f "${SCRIPT_DIR}/verdaccio-config.yaml"
    
    if [[ -n "${DOMAIN:-}" ]]; then
        envsubst < "${SCRIPT_DIR}/verdaccio-deployment.yaml" | kubectl apply -f -
        envsubst < "${SCRIPT_DIR}/verdaccio-ingress.yaml" | kubectl apply -f -
    else
        kubectl apply -f "${SCRIPT_DIR}/verdaccio-deployment.yaml"
    fi
    
    kubectl apply -f "${SCRIPT_DIR}/verdaccio-service.yaml"
    
    # Wait for deployment
    info "Waiting for Verdaccio deployment..."
    kubectl rollout status deployment/verdaccio -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    success "NPM Registry installed successfully!"
    
    # Display access information
    info "NPM Registry Access Information:"
    echo "  Internal URL: http://verdaccio.${COMPONENT_NAMESPACE}.svc.cluster.local:4873"
    
    if [[ -n "${DOMAIN:-}" ]]; then
        echo "  External URL: https://npm.${DOMAIN}"
        echo ""
        echo "Configure npm to use this registry:"
        echo "  npm config set registry https://npm.${DOMAIN}"
        echo ""
        echo "For scoped packages:"
        echo "  npm config set @yourscope:registry https://npm.${DOMAIN}"
    else
        echo "  External URL: http://<node-ip>:30873"
        echo ""
        echo "Configure npm to use this registry:"
        echo "  npm config set registry http://<node-ip>:30873"
    fi
    
    echo ""
    echo "To publish packages:"
    echo "  npm adduser --registry <registry-url>"
    echo "  npm publish --registry <registry-url>"
}

uninstall_npm_registry() {
    info "Uninstalling NPM Registry..."
    
    kubectl delete ingress verdaccio -n ${COMPONENT_NAMESPACE} --ignore-not-found
    kubectl delete service verdaccio verdaccio-nodeport -n ${COMPONENT_NAMESPACE} --ignore-not-found
    kubectl delete deployment verdaccio -n ${COMPONENT_NAMESPACE} --ignore-not-found
    kubectl delete configmap verdaccio-config -n ${COMPONENT_NAMESPACE} --ignore-not-found
    kubectl delete pvc verdaccio-storage -n ${COMPONENT_NAMESPACE} --ignore-not-found
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "NPM Registry uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_npm_registry
        ;;
    uninstall)
        uninstall_npm_registry
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac