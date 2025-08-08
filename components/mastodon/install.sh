#!/bin/bash
set -euo pipefail

# Mastodon Component Installation
# Provides federated social network

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="mastodon"
COMPONENT_NAMESPACE="mastodon"

install_mastodon() {
    info "Installing Mastodon..."
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for Mastodon installation"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate secrets
    POSTGRES_PASSWORD=$(generate_password)
    REDIS_PASSWORD=$(generate_password)
    SECRET_KEY_BASE=$(openssl rand -hex 64)
    OTP_SECRET=$(openssl rand -hex 64)
    
    # Generate VAPID keys
    info "Generating VAPID keys..."
    VAPID_KEYS=$(docker run --rm tootsuite/mastodon:latest bundle exec rake mastodon:webpush:generate_vapid_key 2>/dev/null || echo "VAPID_PRIVATE_KEY=\nVAPID_PUBLIC_KEY=")
    VAPID_PRIVATE_KEY=$(echo "$VAPID_KEYS" | grep VAPID_PRIVATE_KEY | cut -d= -f2)
    VAPID_PUBLIC_KEY=$(echo "$VAPID_KEYS" | grep VAPID_PUBLIC_KEY | cut -d= -f2)
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/mastodon.conf" <<EOF
MASTODON_DOMAIN=social.${DOMAIN}
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
SECRET_KEY_BASE=$SECRET_KEY_BASE
OTP_SECRET=$OTP_SECRET
VAPID_PRIVATE_KEY=$VAPID_PRIVATE_KEY
VAPID_PUBLIC_KEY=$VAPID_PUBLIC_KEY
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/mastodon.conf"
    
    # Create secrets
    kubectl create secret generic mastodon-secrets \
        --namespace=${COMPONENT_NAMESPACE} \
        --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
        --from-literal=redis-password="${REDIS_PASSWORD}" \
        --from-literal=secret-key-base="${SECRET_KEY_BASE}" \
        --from-literal=otp-secret="${OTP_SECRET}" \
        --from-literal=vapid-private-key="${VAPID_PRIVATE_KEY}" \
        --from-literal=vapid-public-key="${VAPID_PUBLIC_KEY}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy PostgreSQL
    info "Deploying PostgreSQL for Mastodon..."
    envsubst < "${SCRIPT_DIR}/postgres-deployment.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/postgres-service.yaml"
    
    # Deploy Redis
    info "Deploying Redis for Mastodon..."
    envsubst < "${SCRIPT_DIR}/redis-deployment.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/redis-service.yaml"
    
    # Wait for databases
    kubectl wait --for=condition=ready pod -l app=mastodon-postgres -n ${COMPONENT_NAMESPACE} --timeout=300s
    kubectl wait --for=condition=ready pod -l app=mastodon-redis -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Create Mastodon config
    envsubst < "${SCRIPT_DIR}/mastodon-config.yaml" | kubectl apply -f -
    
    # Deploy Mastodon web
    info "Deploying Mastodon web..."
    kubectl apply -f "${SCRIPT_DIR}/mastodon-web-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/mastodon-web-service.yaml"
    
    # Deploy Mastodon streaming
    info "Deploying Mastodon streaming..."
    kubectl apply -f "${SCRIPT_DIR}/mastodon-streaming-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/mastodon-streaming-service.yaml"
    
    # Deploy Mastodon sidekiq
    info "Deploying Mastodon sidekiq..."
    kubectl apply -f "${SCRIPT_DIR}/mastodon-sidekiq-deployment.yaml"
    
    # Deploy ingresses
    envsubst < "${SCRIPT_DIR}/mastodon-ingress.yaml" | kubectl apply -f -
    
    # Run database migrations
    info "Running database migrations..."
    kubectl apply -f "${SCRIPT_DIR}/mastodon-db-migrate-job.yaml"
    kubectl wait --for=condition=complete job/mastodon-db-migrate -n ${COMPONENT_NAMESPACE} --timeout=600s
    
    # Wait for deployments
    info "Waiting for Mastodon deployments..."
    kubectl rollout status deployment/mastodon-web -n ${COMPONENT_NAMESPACE} --timeout=300s
    kubectl rollout status deployment/mastodon-streaming -n ${COMPONENT_NAMESPACE} --timeout=300s
    kubectl rollout status deployment/mastodon-sidekiq -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    success "Mastodon installed successfully!"
    
    # Display access information
    info "Mastodon Access Information:"
    echo "  URL: https://social.${DOMAIN}"
    echo ""
    echo "To create admin user:"
    echo "  kubectl exec -it deployment/mastodon-web -n mastodon -- bin/tootctl accounts create <username> --email <email> --confirmed --role Owner"
    echo ""
    echo "Credentials saved to: ${SCRIPT_DIR}/../../.cluster/credentials/mastodon.conf"
}

uninstall_mastodon() {
    info "Uninstalling Mastodon..."
    
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "Mastodon uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_mastodon
        ;;
    uninstall)
        uninstall_mastodon
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac