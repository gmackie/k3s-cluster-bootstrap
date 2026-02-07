#!/bin/bash
set -euo pipefail

# Moodle LMS Installation
# Learning management system for LTI integration testing
# Uses ellakcy/moodle Docker image with PostgreSQL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="moodle"
COMPONENT_NAMESPACE="moodle"

install_moodle() {
    info "Installing Moodle LMS..."

    if [[ -z "${DOMAIN:-}" ]]; then
        error "DOMAIN is required for Moodle installation"
    fi

    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    # Generate passwords
    MOODLE_PASSWORD=$(generate_password)
    POSTGRES_PASSWORD=$(generate_password)

    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/moodle.conf" <<EOF
MOODLE_URL=https://moodle.${DOMAIN}
ADMIN_USER=admin
ADMIN_PASSWORD=${MOODLE_PASSWORD}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# LTI 1.3 Configuration
# After installation, configure LTI tools at:
# Site Administration → Plugins → Activity modules → External tool

# Authentik SSO (manual configuration required)
# 1. Create OIDC provider in Authentik for Moodle
# 2. In Moodle: Site Administration → Plugins → Authentication → OpenID Connect
# 3. Configure with Authentik endpoints
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/moodle.conf"

    # Create secrets
    info "Creating Moodle secrets..."
    kubectl create secret generic moodle-secrets \
        --namespace=${COMPONENT_NAMESPACE} \
        --from-literal=admin-password="${MOODLE_PASSWORD}" \
        --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Export for envsubst
    export DOMAIN

    # Deploy PostgreSQL
    info "Deploying PostgreSQL for Moodle..."
    kubectl apply -f "${SCRIPT_DIR}/moodle-postgres.yaml"

    # Wait for PostgreSQL
    info "Waiting for PostgreSQL..."
    kubectl wait --for=condition=ready pod -l app=moodle-postgres -n ${COMPONENT_NAMESPACE} --timeout=300s

    # Deploy Moodle
    info "Deploying Moodle application..."
    envsubst < "${SCRIPT_DIR}/moodle-deployment.yaml" | kubectl apply -f -

    # Deploy ingress
    info "Deploying Moodle ingress..."
    envsubst < "${SCRIPT_DIR}/moodle-ingress.yaml" | kubectl apply -f -

    # Wait for deployment (Moodle first boot does DB setup)
    info "Waiting for Moodle deployment (first boot may take several minutes)..."
    kubectl rollout status deployment/moodle -n ${COMPONENT_NAMESPACE} --timeout=900s || {
        warn "Moodle deployment is taking longer than expected."
        warn "Check logs with: kubectl logs -n moodle -l app=moodle"
    }

    success "Moodle installed successfully!"
    info ""
    info "=== Moodle Access Information ==="
    info "URL: https://moodle.${DOMAIN}"
    info "Admin User: admin"
    info "Admin Password: See .cluster/credentials/moodle.conf"
    info ""
    info "=== LTI 1.3 Setup ==="
    info "1. Login as admin"
    info "2. Site Administration → Plugins → Activity modules → External tool"
    info "3. Manage tools → Configure a tool manually"
    info ""
    info "=== Authentik SSO Setup (optional) ==="
    info "1. Create OIDC provider in Authentik for 'Moodle LMS'"
    info "2. In Moodle: Site Administration → Plugins → Authentication → Manage authentication"
    info "3. Enable OAuth 2 authentication"
    info "4. Configure OAuth 2 service with Authentik endpoints"
}

uninstall_moodle() {
    info "Uninstalling Moodle..."

    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found --timeout=120s || {
        warn "Namespace deletion timed out. Forcing..."
        kubectl delete namespace ${COMPONENT_NAMESPACE} --force --grace-period=0 || true
    }

    success "Moodle uninstalled!"
}

# Main execution
case "${1:-install}" in
    install)
        install_moodle
        ;;
    uninstall)
        uninstall_moodle
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        ;;
esac
