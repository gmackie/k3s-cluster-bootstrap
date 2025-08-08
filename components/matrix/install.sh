#!/bin/bash
set -euo pipefail

# Matrix (Synapse) Component Installation
# Provides federated chat server

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="matrix"
COMPONENT_NAMESPACE="matrix"

install_matrix() {
    info "Installing Matrix (Synapse) server..."
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for Matrix installation"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate secrets
    MATRIX_POSTGRES_PASSWORD=$(generate_password)
    MATRIX_REGISTRATION_SHARED_SECRET=$(openssl rand -hex 32)
    MATRIX_MACAROON_SECRET_KEY=$(openssl rand -hex 32)
    MATRIX_FORM_SECRET=$(openssl rand -hex 32)
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/matrix.conf" <<EOF
MATRIX_DOMAIN=matrix.${DOMAIN}
MATRIX_SERVER_NAME=${DOMAIN}
POSTGRES_PASSWORD=$MATRIX_POSTGRES_PASSWORD
REGISTRATION_SHARED_SECRET=$MATRIX_REGISTRATION_SHARED_SECRET
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/matrix.conf"
    
    # Create secrets
    kubectl create secret generic matrix-secrets \
        --namespace=${COMPONENT_NAMESPACE} \
        --from-literal=postgres-password="${MATRIX_POSTGRES_PASSWORD}" \
        --from-literal=registration-shared-secret="${MATRIX_REGISTRATION_SHARED_SECRET}" \
        --from-literal=macaroon-secret-key="${MATRIX_MACAROON_SECRET_KEY}" \
        --from-literal=form-secret="${MATRIX_FORM_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy PostgreSQL
    info "Deploying PostgreSQL for Matrix..."
    envsubst < "${SCRIPT_DIR}/postgres-deployment.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/postgres-service.yaml"
    
    # Wait for PostgreSQL
    kubectl wait --for=condition=ready pod -l app=matrix-postgres -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Create Synapse config
    info "Creating Synapse configuration..."
    envsubst < "${SCRIPT_DIR}/synapse-config.yaml" | kubectl apply -f -
    
    # Deploy Synapse
    kubectl apply -f "${SCRIPT_DIR}/synapse-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/synapse-service.yaml"
    
    # Deploy ingresses
    info "Deploying Matrix ingresses..."
    # Client-server API (with OAuth)
    envsubst < "${SCRIPT_DIR}/matrix-ingress.yaml" | kubectl apply -f -
    # Federation API (no OAuth)
    envsubst < "${SCRIPT_DIR}/matrix-federation-ingress.yaml" | kubectl apply -f -
    
    # Deploy Element web client
    info "Deploying Element web client..."
    envsubst < "${SCRIPT_DIR}/element-config.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/element-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/element-service.yaml"
    envsubst < "${SCRIPT_DIR}/element-ingress.yaml" | kubectl apply -f -
    
    # Wait for deployments
    info "Waiting for Matrix deployment..."
    kubectl rollout status deployment/synapse -n ${COMPONENT_NAMESPACE} --timeout=300s
    kubectl rollout status deployment/element -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    success "Matrix installed successfully!"
    
    # Display access information
    info "Matrix Access Information:"
    echo "  Matrix homeserver: https://matrix.${DOMAIN}"
    echo "  Element web client: https://chat.${DOMAIN}"
    echo "  Server name: ${DOMAIN}"
    echo ""
    echo "Federation is available at: https://matrix.${DOMAIN}:8448"
    echo ""
    echo "To create admin user:"
    echo "  kubectl exec -it deployment/synapse -n matrix -- register_new_matrix_user -c /data/homeserver.yaml"
    echo ""
    echo "Credentials saved to: ${SCRIPT_DIR}/../../.cluster/credentials/matrix.conf"
}

uninstall_matrix() {
    info "Uninstalling Matrix..."
    
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "Matrix uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_matrix
        ;;
    uninstall)
        uninstall_matrix
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac