#!/bin/bash
set -euo pipefail

# Vaultwarden Component Installation
# Self-hosted password manager compatible with Bitwarden

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="vaultwarden"
COMPONENT_NAMESPACE="vaultwarden"

install_vaultwarden() {
    info "Installing Vaultwarden password manager..."
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for Vaultwarden installation"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate secrets
    ADMIN_TOKEN=$(openssl rand -base64 48)
    DATABASE_PASSWORD=$(generate_password)
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/vaultwarden.conf" <<EOF
VAULTWARDEN_URL=https://vault.${DOMAIN}
ADMIN_TOKEN=$ADMIN_TOKEN
DATABASE_PASSWORD=$DATABASE_PASSWORD
ADMIN_PANEL_URL=https://vault.${DOMAIN}/admin
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/vaultwarden.conf"
    
    # Create secrets
    kubectl create secret generic vaultwarden-secrets \
        --namespace=${COMPONENT_NAMESPACE} \
        --from-literal=admin-token="${ADMIN_TOKEN}" \
        --from-literal=database-password="${DATABASE_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy PostgreSQL
    info "Deploying PostgreSQL for Vaultwarden..."
    kubectl apply -f "${SCRIPT_DIR}/vaultwarden-postgres-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/vaultwarden-postgres-service.yaml"
    
    # Wait for PostgreSQL
    kubectl wait --for=condition=ready pod -l app=vaultwarden-postgres -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Deploy Vaultwarden
    info "Deploying Vaultwarden..."
    kubectl apply -f "${SCRIPT_DIR}/vaultwarden-pvc.yaml"
    envsubst < "${SCRIPT_DIR}/vaultwarden-deployment.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/vaultwarden-service.yaml"
    envsubst < "${SCRIPT_DIR}/vaultwarden-ingress.yaml" | kubectl apply -f -
    
    # Wait for deployment
    info "Waiting for Vaultwarden deployment..."
    kubectl rollout status deployment/vaultwarden -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    success "Vaultwarden installed successfully!"
    
    # Display access information
    info "Vaultwarden Access Information:"
    echo "  URL: https://vault.${DOMAIN}"
    echo "  Admin Panel: https://vault.${DOMAIN}/admin"
    echo "  Admin Token: Saved in credentials file"
    echo ""
    echo "Initial Setup:"
    echo "  1. Access the admin panel with the admin token"
    echo "  2. Configure SMTP settings if available"
    echo "  3. Invite users via the admin panel"
    echo "  4. Users can register using invitation links"
    echo ""
    echo "Security Notes:"
    echo "  - Signups are disabled by default"
    echo "  - Only invited users can register"
    echo "  - Admin token is required for admin access"
    echo "  - OAuth protects web UI access"
    echo "  - API endpoints remain open for app access"
    echo ""
    echo "Mobile/Desktop App Configuration:"
    echo "  Server URL: https://vault.${DOMAIN}"
    echo ""
    echo "Credentials saved to: ${SCRIPT_DIR}/../../.cluster/credentials/vaultwarden.conf"
}

uninstall_vaultwarden() {
    info "Uninstalling Vaultwarden..."
    
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "Vaultwarden uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_vaultwarden
        ;;
    uninstall)
        uninstall_vaultwarden
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac