#!/bin/bash
set -euo pipefail

# Nextcloud Component Installation
# Self-hosted file sync and collaboration platform

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="nextcloud"
COMPONENT_NAMESPACE="nextcloud"

install_nextcloud() {
    info "Installing Nextcloud file sharing and collaboration platform..."
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for Nextcloud installation"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Check if MinIO is installed (optional but recommended)
    if kubectl get namespace minio &>/dev/null; then
        info "MinIO detected - will configure S3 primary storage"
        USE_S3="true"
        
        # Get MinIO credentials
        if [[ -f "${SCRIPT_DIR}/../../.cluster/credentials/minio.conf" ]]; then
            source "${SCRIPT_DIR}/../../.cluster/credentials/minio.conf"
            S3_ACCESS_KEY="${MINIO_ROOT_USER}"
            S3_SECRET_KEY="${MINIO_ROOT_PASSWORD}"
        else
            warn "MinIO credentials not found - will use local storage"
            USE_S3="false"
        fi
    else
        info "MinIO not detected - will use local storage"
        USE_S3="false"
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate secrets
    ADMIN_PASSWORD=$(generate_password)
    DATABASE_PASSWORD=$(generate_password)
    REDIS_PASSWORD=$(generate_password)
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/nextcloud.conf" <<EOF
NEXTCLOUD_URL=https://files.${DOMAIN}
ADMIN_USER=admin
ADMIN_PASSWORD=$ADMIN_PASSWORD
DATABASE_PASSWORD=$DATABASE_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD

# WebDAV URLs
WEBDAV_URL=https://files.${DOMAIN}/remote.php/dav/files/admin/
CARDDAV_URL=https://files.${DOMAIN}/remote.php/dav/addressbooks/users/admin/
CALDAV_URL=https://files.${DOMAIN}/remote.php/dav/calendars/admin/

# Sync Client Configuration
# Desktop: https://nextcloud.com/install/#install-clients
# Mobile: Available on App Store and Google Play
# Server Address: https://files.${DOMAIN}
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/nextcloud.conf"
    
    # Create secrets
    if [[ "$USE_S3" == "true" ]]; then
        kubectl create secret generic nextcloud-secrets \
            --namespace=${COMPONENT_NAMESPACE} \
            --from-literal=admin-password="${ADMIN_PASSWORD}" \
            --from-literal=database-password="${DATABASE_PASSWORD}" \
            --from-literal=redis-password="${REDIS_PASSWORD}" \
            --from-literal=s3-access-key="${S3_ACCESS_KEY}" \
            --from-literal=s3-secret-key="${S3_SECRET_KEY}" \
            --dry-run=client -o yaml | kubectl apply -f -
    else
        kubectl create secret generic nextcloud-secrets \
            --namespace=${COMPONENT_NAMESPACE} \
            --from-literal=admin-password="${ADMIN_PASSWORD}" \
            --from-literal=database-password="${DATABASE_PASSWORD}" \
            --from-literal=redis-password="${REDIS_PASSWORD}" \
            --from-literal=s3-access-key="" \
            --from-literal=s3-secret-key="" \
            --dry-run=client -o yaml | kubectl apply -f -
    fi
    
    # Deploy PostgreSQL
    info "Deploying PostgreSQL for Nextcloud..."
    kubectl apply -f "${SCRIPT_DIR}/nextcloud-postgres-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/nextcloud-postgres-service.yaml"
    
    # Deploy Redis
    info "Deploying Redis for caching..."
    kubectl apply -f "${SCRIPT_DIR}/nextcloud-redis-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/nextcloud-redis-service.yaml"
    
    # Wait for dependencies
    kubectl wait --for=condition=ready pod -l app=nextcloud-postgres -n ${COMPONENT_NAMESPACE} --timeout=300s
    kubectl wait --for=condition=ready pod -l app=nextcloud-redis -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Create MinIO bucket if using S3
    if [[ "$USE_S3" == "true" ]]; then
        info "Creating Nextcloud bucket in MinIO..."
        kubectl run --rm -i --image=minio/mc:latest mc-create-bucket -n minio --restart=Never -- /bin/sh -c "
            mc alias set minio http://minio:9000 ${S3_ACCESS_KEY} ${S3_SECRET_KEY}
            mc mb --ignore-existing minio/nextcloud
            mc policy set download minio/nextcloud
        " || true
    fi
    
    # Deploy Nextcloud
    info "Deploying Nextcloud..."
    kubectl apply -f "${SCRIPT_DIR}/nextcloud-pvc.yaml"
    envsubst < "${SCRIPT_DIR}/nextcloud-deployment.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/nextcloud-service.yaml"
    envsubst < "${SCRIPT_DIR}/nextcloud-ingress.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/nextcloud-cronjob.yaml"
    
    # Wait for deployment
    info "Waiting for Nextcloud deployment..."
    kubectl rollout status deployment/nextcloud -n ${COMPONENT_NAMESPACE} --timeout=600s
    
    # Initial configuration
    info "Running initial Nextcloud configuration..."
    sleep 30  # Give Nextcloud time to initialize
    
    # Configure Nextcloud settings
    kubectl exec -n ${COMPONENT_NAMESPACE} deployment/nextcloud -- su -s /bin/bash www-data -c "
        php occ config:system:set default_phone_region --value US
        php occ config:system:set force_language --value en
        php occ config:system:set default_language --value en
        php occ config:system:set skeletondirectory --value ''
        php occ background:cron
        php occ config:system:set maintenance_window_start --value 1
    " || true
    
    success "Nextcloud installed successfully!"
    
    # Display access information
    info "Nextcloud Access Information:"
    echo "  URL: https://files.${DOMAIN}"
    echo "  Admin User: admin"
    echo "  Admin Password: Saved in credentials file"
    echo ""
    echo "Features Enabled:"
    echo "  ✓ File sync and sharing"
    echo "  ✓ Calendar and contacts"
    echo "  ✓ Document collaboration"
    echo "  ✓ Video calls (Talk app)"
    echo "  ✓ Notes and tasks"
    if [[ "$USE_S3" == "true" ]]; then
        echo "  ✓ S3 primary storage (MinIO)"
    fi
    echo ""
    echo "Client Configuration:"
    echo "  Desktop/Mobile Apps: Use server https://files.${DOMAIN}"
    echo "  WebDAV: https://files.${DOMAIN}/remote.php/dav/"
    echo ""
    echo "Recommended Apps to Install:"
    echo "  - Collabora Online (Office suite)"
    echo "  - Talk (Video conferencing)"
    echo "  - Deck (Kanban boards)"
    echo "  - Forms (Surveys)"
    echo "  - Maps (Location sharing)"
    echo ""
    echo "Security Notes:"
    echo "  - Web interface protected by OAuth"
    echo "  - Sync clients use Nextcloud credentials"
    echo "  - Enable 2FA in user settings"
    echo ""
    echo "Credentials saved to: ${SCRIPT_DIR}/../../.cluster/credentials/nextcloud.conf"
}

uninstall_nextcloud() {
    info "Uninstalling Nextcloud..."
    
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "Nextcloud uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_nextcloud
        ;;
    uninstall)
        uninstall_nextcloud
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac