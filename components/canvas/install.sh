#!/bin/bash
set -euo pipefail

# Canvas LMS Installation
# Instructure Canvas for LTI integration testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="canvas"
COMPONENT_NAMESPACE="canvas"

install_canvas() {
    info "Installing Canvas LMS..."

    if [[ -z "${DOMAIN:-}" ]]; then
        error "DOMAIN is required for Canvas installation"
    fi

    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    # Generate secrets
    CANVAS_ADMIN_PASSWORD=$(generate_password)
    CANVAS_DB_PASSWORD=$(generate_password)
    CANVAS_ENCRYPTION_KEY=$(openssl rand -hex 32)
    CANVAS_SIGNING_KEY=$(openssl rand -hex 32)

    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/canvas.conf" <<EOF
CANVAS_URL=https://canvas.${DOMAIN}
ADMIN_EMAIL=admin@${DOMAIN}
ADMIN_PASSWORD=${CANVAS_ADMIN_PASSWORD}
DB_PASSWORD=${CANVAS_DB_PASSWORD}
ENCRYPTION_KEY=${CANVAS_ENCRYPTION_KEY}
SIGNING_KEY=${CANVAS_SIGNING_KEY}

# LTI 1.3 Configuration
# After installation, configure LTI Developer Keys at:
# Admin → Developer Keys → + Developer Key → + LTI Key

# Authentik SSO (manual configuration required)
# 1. Create OIDC provider in Authentik for 'Canvas LMS'
# 2. In Canvas: Admin → Authentication → + Provider → OpenID Connect
# 3. Configure with Authentik endpoints
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/canvas.conf"

    # Create canvas secrets
    info "Creating Canvas secrets..."
    kubectl create secret generic canvas-secrets \
        --namespace=${COMPONENT_NAMESPACE} \
        --from-literal=admin-password="${CANVAS_ADMIN_PASSWORD}" \
        --from-literal=encryption-key="${CANVAS_ENCRYPTION_KEY}" \
        --from-literal=signing-key="${CANVAS_SIGNING_KEY}" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Export for envsubst
    export DOMAIN
    export CANVAS_DB_PASSWORD
    export CANVAS_ENCRYPTION_KEY
    export CANVAS_SIGNING_KEY

    # Deploy PostgreSQL
    info "Deploying PostgreSQL for Canvas..."
    envsubst < "${SCRIPT_DIR}/canvas-postgres.yaml" | kubectl apply -f -

    # Deploy Redis
    info "Deploying Redis..."
    kubectl apply -f "${SCRIPT_DIR}/canvas-redis.yaml"

    # Wait for dependencies
    info "Waiting for PostgreSQL..."
    kubectl wait --for=condition=ready pod -l app=canvas-postgres -n ${COMPONENT_NAMESPACE} --timeout=300s

    info "Waiting for Redis..."
    kubectl wait --for=condition=ready pod -l app=canvas-redis -n ${COMPONENT_NAMESPACE} --timeout=120s

    # Deploy Canvas configuration
    info "Deploying Canvas configuration..."
    envsubst < "${SCRIPT_DIR}/canvas-config.yaml" | kubectl apply -f -

    # Deploy Canvas web
    info "Deploying Canvas web application..."
    envsubst < "${SCRIPT_DIR}/canvas-web.yaml" | kubectl apply -f -

    # Deploy Canvas jobs worker
    info "Deploying Canvas background jobs..."
    envsubst < "${SCRIPT_DIR}/canvas-jobs.yaml" | kubectl apply -f -

    # Deploy ingress
    info "Deploying Canvas ingress..."
    envsubst < "${SCRIPT_DIR}/canvas-ingress.yaml" | kubectl apply -f -

    # Wait for deployment (Canvas takes a while to start)
    info "Waiting for Canvas deployment (this may take several minutes)..."
    kubectl rollout status deployment/canvas-web -n ${COMPONENT_NAMESPACE} --timeout=900s || {
        warn "Canvas web deployment is taking longer than expected."
        warn "Check logs with: kubectl logs -n canvas -l app=canvas-web"
    }

    success "Canvas installed successfully!"
    info ""
    info "=== Canvas Access Information ==="
    info "URL: https://canvas.${DOMAIN}"
    info "Admin Email: admin@${DOMAIN}"
    info "Admin Password: See .cluster/credentials/canvas.conf"
    info ""
    info "NOTE: Canvas may take several minutes to fully initialize on first boot."
    info "      Check status with: kubectl get pods -n canvas"
    info ""
    info "=== LTI 1.3 Setup ==="
    info "1. Login as admin"
    info "2. Admin → Developer Keys"
    info "3. + Developer Key → + LTI Key"
    info "4. Configure your tool and enable the key"
    info ""
    info "=== Authentik SSO Setup (optional) ==="
    info "1. Create OIDC provider in Authentik for 'Canvas LMS'"
    info "2. In Canvas: Admin → Authentication → + Provider"
    info "3. Select OpenID Connect"
    info "4. Configure with Authentik endpoints"
}

uninstall_canvas() {
    info "Uninstalling Canvas..."

    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found --timeout=120s || {
        warn "Namespace deletion timed out. Forcing..."
        kubectl delete namespace ${COMPONENT_NAMESPACE} --force --grace-period=0 || true
    }

    success "Canvas uninstalled!"
}

# Main execution
case "${1:-install}" in
    install)
        install_canvas
        ;;
    uninstall)
        uninstall_canvas
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        ;;
esac
