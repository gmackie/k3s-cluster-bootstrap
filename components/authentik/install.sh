#!/bin/bash
set -euo pipefail

# Authentik Component Installation
# Self-hosted identity provider with support for SAML, OAuth, LDAP

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="authentik"
COMPONENT_NAMESPACE="authentik"

install_authentik() {
    info "Installing Authentik identity provider..."
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for Authentik installation"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate secrets
    SECRET_KEY=$(openssl rand -base64 50 | tr -d '\n')
    POSTGRES_PASSWORD=$(generate_password)
    REDIS_PASSWORD=$(generate_password)
    BOOTSTRAP_PASSWORD=$(generate_password)
    BOOTSTRAP_TOKEN=$(openssl rand -hex 32)
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/authentik.conf" <<EOF
AUTHENTIK_URL=https://auth.${DOMAIN}
ADMIN_USER=akadmin
ADMIN_PASSWORD=$BOOTSTRAP_PASSWORD
BOOTSTRAP_TOKEN=$BOOTSTRAP_TOKEN
SECRET_KEY=$SECRET_KEY
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD

# API Access
# Use the bootstrap token for initial API access:
# curl -H "Authorization: Bearer $BOOTSTRAP_TOKEN" https://auth.${DOMAIN}/api/v3/

# OAuth2 Provider Setup
# 1. Login to Authentik
# 2. Create OAuth2/OpenID Provider
# 3. Create Application
# 4. Get Client ID and Secret

# SAML Provider Setup
# 1. Create SAML Provider
# 2. Configure metadata
# 3. Download signing certificate

# LDAP Outpost
# 1. Create LDAP Provider
# 2. Deploy outpost
# 3. Configure bind DN and password
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/authentik.conf"
    
    # Create secrets
    kubectl create secret generic authentik-secrets \
        --namespace=${COMPONENT_NAMESPACE} \
        --from-literal=secret-key="${SECRET_KEY}" \
        --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
        --from-literal=redis-password="${REDIS_PASSWORD}" \
        --from-literal=bootstrap-password="${BOOTSTRAP_PASSWORD}" \
        --from-literal=bootstrap-token="${BOOTSTRAP_TOKEN}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy PostgreSQL
    info "Deploying PostgreSQL for Authentik..."
    kubectl apply -f "${SCRIPT_DIR}/authentik-postgres-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/authentik-postgres-service.yaml"
    
    # Deploy Redis
    info "Deploying Redis..."
    kubectl apply -f "${SCRIPT_DIR}/authentik-redis-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/authentik-redis-service.yaml"
    
    # Wait for dependencies
    kubectl wait --for=condition=ready pod -l app=authentik-postgres -n ${COMPONENT_NAMESPACE} --timeout=300s
    kubectl wait --for=condition=ready pod -l app=authentik-redis -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Deploy Authentik configuration
    info "Deploying Authentik configuration..."
    envsubst < "${SCRIPT_DIR}/authentik-config.yaml" | kubectl apply -f -
    
    # Deploy Authentik server
    info "Deploying Authentik server..."
    envsubst < "${SCRIPT_DIR}/authentik-server-deployment.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/authentik-server-service.yaml"
    
    # Deploy Authentik worker
    info "Deploying Authentik worker..."
    kubectl apply -f "${SCRIPT_DIR}/authentik-worker-deployment.yaml"
    
    # Deploy ingress
    envsubst < "${SCRIPT_DIR}/authentik-ingress.yaml" | kubectl apply -f -
    
    # Wait for deployment
    info "Waiting for Authentik deployment..."
    kubectl rollout status deployment/authentik-server -n ${COMPONENT_NAMESPACE} --timeout=600s
    kubectl rollout status deployment/authentik-worker -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    success "Authentik installed successfully!"
    
    # Display access information
    info "Authentik Access Information:"
    echo "  URL: https://auth.${DOMAIN}"
    echo "  Admin User: akadmin"
    echo "  Admin Password: Saved in credentials file"
    echo ""
    echo "Features:"
    echo "  ✓ OAuth2/OpenID Connect provider"
    echo "  ✓ SAML provider"
    echo "  ✓ LDAP provider"
    echo "  ✓ Proxy authentication"
    echo "  ✓ User management and flows"
    echo "  ✓ Multi-factor authentication"
    echo "  ✓ Social login integration"
    echo "  ✓ Application catalog"
    echo ""
    echo "Common Use Cases:"
    echo "  1. Replace GitHub OAuth with Authentik OAuth"
    echo "  2. Add SAML authentication to applications"
    echo "  3. Provide LDAP for legacy applications"
    echo "  4. Implement custom authentication flows"
    echo "  5. Add MFA to all applications"
    echo ""
    echo "Next Steps:"
    echo "  1. Login to Authentik"
    echo "  2. Create providers (OAuth2, SAML, LDAP)"
    echo "  3. Create applications"
    echo "  4. Configure authentication flows"
    echo "  5. Set up user sources (LDAP, OAuth)"
    echo ""
    echo "To integrate with existing services:"
    echo "  1. Create OAuth2 provider in Authentik"
    echo "  2. Update service to use Authentik OAuth"
    echo "  3. Test authentication flow"
    echo ""
    echo "Credentials saved to: ${SCRIPT_DIR}/../../.cluster/credentials/authentik.conf"
}

uninstall_authentik() {
    info "Uninstalling Authentik..."
    
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "Authentik uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_authentik
        ;;
    uninstall)
        uninstall_authentik
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac