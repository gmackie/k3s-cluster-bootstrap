#!/bin/bash
set -euo pipefail

# Sentry Component Installation
# Application error tracking and performance monitoring

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="sentry"
COMPONENT_NAMESPACE="sentry"

install_sentry() {
    info "Installing Sentry error tracking..."
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for Sentry installation"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate secrets
    SECRET_KEY=$(openssl rand -base64 32)
    POSTGRES_PASSWORD=$(generate_password)
    ADMIN_PASSWORD=$(generate_password)
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/sentry.conf" <<EOF
SENTRY_URL=https://sentry.${DOMAIN}
ADMIN_EMAIL=admin@${DOMAIN}
ADMIN_PASSWORD=$ADMIN_PASSWORD
SECRET_KEY=$SECRET_KEY
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# DSN for your applications will be available after creating a project
# Example: https://<public_key>@sentry.${DOMAIN}/<project_id>

# SDK Configuration Examples:

# JavaScript/TypeScript
# import * as Sentry from "@sentry/browser";
# Sentry.init({
#   dsn: "https://<public_key>@sentry.${DOMAIN}/<project_id>",
#   environment: "production",
# });

# Python
# import sentry_sdk
# sentry_sdk.init(
#     dsn="https://<public_key>@sentry.${DOMAIN}/<project_id>",
#     environment="production",
# )

# Go
# import "github.com/getsentry/sentry-go"
# sentry.Init(sentry.ClientOptions{
#     Dsn: "https://<public_key>@sentry.${DOMAIN}/<project_id>",
#     Environment: "production",
# })
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/sentry.conf"
    
    # Create secrets
    kubectl create secret generic sentry-secrets \
        --namespace=${COMPONENT_NAMESPACE} \
        --from-literal=secret-key="${SECRET_KEY}" \
        --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
        --from-literal=admin-password="${ADMIN_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy PostgreSQL
    info "Deploying PostgreSQL for Sentry..."
    kubectl apply -f "${SCRIPT_DIR}/sentry-postgres-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/sentry-postgres-service.yaml"
    
    # Deploy Redis
    info "Deploying Redis..."
    kubectl apply -f "${SCRIPT_DIR}/sentry-redis-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/sentry-redis-service.yaml"
    
    # Wait for dependencies
    kubectl wait --for=condition=ready pod -l app=sentry-postgres -n ${COMPONENT_NAMESPACE} --timeout=300s
    kubectl wait --for=condition=ready pod -l app=sentry-redis -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Deploy Sentry configuration
    info "Deploying Sentry configuration..."
    envsubst < "${SCRIPT_DIR}/sentry-config.yaml" | kubectl apply -f -
    
    # Deploy Sentry components
    info "Deploying Sentry web service..."
    envsubst < "${SCRIPT_DIR}/sentry-web-deployment.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/sentry-web-service.yaml"
    
    info "Deploying Sentry workers..."
    kubectl apply -f "${SCRIPT_DIR}/sentry-worker-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/sentry-cron-deployment.yaml"
    
    # Deploy ingress
    envsubst < "${SCRIPT_DIR}/sentry-ingress.yaml" | kubectl apply -f -
    
    # Wait for deployment
    info "Waiting for Sentry deployment..."
    kubectl rollout status deployment/sentry-web -n ${COMPONENT_NAMESPACE} --timeout=600s
    kubectl rollout status deployment/sentry-worker -n ${COMPONENT_NAMESPACE} --timeout=300s
    kubectl rollout status deployment/sentry-cron -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    success "Sentry installed successfully!"
    
    # Display access information
    info "Sentry Access Information:"
    echo "  URL: https://sentry.${DOMAIN}"
    echo "  Admin Email: admin@${DOMAIN}"
    echo "  Admin Password: Saved in credentials file"
    echo ""
    echo "Initial Setup:"
    echo "  1. Login with admin credentials"
    echo "  2. Create your organization"
    echo "  3. Create your first project"
    echo "  4. Get the DSN from project settings"
    echo "  5. Configure your applications with the DSN"
    echo ""
    echo "Features:"
    echo "  ✓ Error tracking across all platforms"
    echo "  ✓ Performance monitoring"
    echo "  ✓ Release tracking"
    echo "  ✓ User feedback"
    echo "  ✓ Issue assignment and workflow"
    echo "  ✓ Integrations (Slack, GitHub, etc.)"
    echo ""
    echo "SDK Support:"
    echo "  - JavaScript/TypeScript (Browser & Node.js)"
    echo "  - Python, Django, Flask"
    echo "  - Go"
    echo "  - Ruby"
    echo "  - Java"
    echo "  - .NET"
    echo "  - PHP"
    echo "  - React Native"
    echo "  - Flutter"
    echo "  - And many more..."
    echo ""
    echo "Credentials saved to: ${SCRIPT_DIR}/../../.cluster/credentials/sentry.conf"
}

uninstall_sentry() {
    info "Uninstalling Sentry..."
    
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "Sentry uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_sentry
        ;;
    uninstall)
        uninstall_sentry
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac