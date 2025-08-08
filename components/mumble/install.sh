#!/bin/bash
set -euo pipefail

# Mumble Component Installation
# Provides voice chat server

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="mumble"
COMPONENT_NAMESPACE="mumble"

install_mumble() {
    info "Installing Mumble (Murmur) server..."
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate SuperUser password
    SUPERUSER_PASSWORD=$(generate_password)
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/mumble.conf" <<EOF
MUMBLE_SUPERUSER_PASSWORD=$SUPERUSER_PASSWORD
MUMBLE_SERVER=voice.${DOMAIN:-mumble.local}
MUMBLE_PORT=64738
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/mumble.conf"
    
    # Create config
    info "Creating Mumble configuration..."
    envsubst < "${SCRIPT_DIR}/mumble-config.yaml" | kubectl apply -f -
    
    # Deploy Mumble
    kubectl apply -f "${SCRIPT_DIR}/mumble-deployment.yaml"
    
    # Create services (TCP and UDP)
    kubectl apply -f "${SCRIPT_DIR}/mumble-service.yaml"
    
    # Deploy Mumble web interface (if domain is set)
    if [[ -n "${DOMAIN:-}" ]]; then
        info "Deploying Mumble web interface..."
        kubectl apply -f "${SCRIPT_DIR}/mumble-web-deployment.yaml"
        kubectl apply -f "${SCRIPT_DIR}/mumble-web-service.yaml"
        envsubst < "${SCRIPT_DIR}/mumble-web-ingress.yaml" | kubectl apply -f -
    fi
    
    # Wait for deployment
    info "Waiting for Mumble deployment..."
    kubectl rollout status deployment/mumble -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Set SuperUser password
    info "Setting SuperUser password..."
    sleep 10  # Wait for Mumble to start
    kubectl exec deployment/mumble -n ${COMPONENT_NAMESPACE} -- murmurd -ini /etc/mumble/mumble.ini -supw "$SUPERUSER_PASSWORD" || true
    
    success "Mumble installed successfully!"
    
    # Display access information
    info "Mumble Access Information:"
    echo "  Server: voice.${DOMAIN:-<node-ip>}"
    echo "  Port: 64738 (TCP/UDP)"
    echo "  SuperUser password: Saved to ${SCRIPT_DIR}/../../.cluster/credentials/mumble.conf"
    
    if [[ -n "${DOMAIN:-}" ]]; then
        echo ""
        echo "Web interface: https://voice.${DOMAIN}"
    fi
    
    echo ""
    echo "To connect:"
    echo "  1. Download Mumble client: https://www.mumble.info/downloads/"
    echo "  2. Add server: voice.${DOMAIN:-<node-ip>}:64738"
    echo "  3. Connect with any username (registration allowed)"
}

uninstall_mumble() {
    info "Uninstalling Mumble..."
    
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "Mumble uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_mumble
        ;;
    uninstall)
        uninstall_mumble
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac