#!/bin/bash
set -euo pipefail

# Centralized Authentication Component
# Provides OAuth2 proxy for all cluster services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="auth"
COMPONENT_NAMESPACE="auth-system"

install_auth() {
    info "Installing Centralized Authentication (OAuth2 Proxy)..."
    
    # Check for required environment variables
    if [[ -z "${GITHUB_CLIENT_ID:-}" ]] || [[ -z "${GITHUB_CLIENT_SECRET:-}" ]]; then
        error "GitHub OAuth credentials required!"
        echo "Please set the following environment variables:"
        echo "  export GITHUB_CLIENT_ID=<your-github-oauth-app-client-id>"
        echo "  export GITHUB_CLIENT_SECRET=<your-github-oauth-app-client-secret>"
        echo ""
        echo "Create a GitHub OAuth App at: https://github.com/settings/applications/new"
        echo "  Homepage URL: https://${DOMAIN}"
        echo "  Authorization callback URL: https://${DOMAIN}/oauth2/callback"
        exit 1
    fi
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for centralized authentication"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate cookie secret if not provided
    if [[ -z "${OAUTH2_PROXY_COOKIE_SECRET:-}" ]]; then
        export OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -base64 32 | tr -d '\n')
        info "Generated cookie secret"
    fi
    
    # Create secrets
    info "Creating OAuth2 proxy secrets..."
    envsubst < "${SCRIPT_DIR}/oauth2-proxy-secret.yaml" | kubectl apply -f -
    
    # Create config
    info "Creating OAuth2 proxy configuration..."
    envsubst < "${SCRIPT_DIR}/oauth2-proxy-config.yaml" | kubectl apply -f -
    
    # Deploy OAuth2 proxy
    kubectl apply -f "${SCRIPT_DIR}/oauth2-proxy-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/oauth2-proxy-service.yaml"
    
    # Create ingress for root domain and OAuth2 endpoints
    envsubst < "${SCRIPT_DIR}/oauth2-proxy-ingress.yaml" | kubectl apply -f -
    
    # Wait for deployment
    info "Waiting for OAuth2 proxy deployment..."
    kubectl rollout status deployment/oauth2-proxy -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    success "Centralized Authentication installed successfully!"
    
    # Display configuration info
    info "Authentication Configuration:"
    echo "  Root Domain: https://${DOMAIN}"
    echo "  OAuth2 Endpoints: https://${DOMAIN}/oauth2/*"
    echo ""
    echo "GitHub OAuth Configuration:"
    echo "  Allowed Users: Set GITHUB_USER or GITHUB_ORG environment variables"
    echo "  Current Org: ${GITHUB_ORG:-not set}"
    echo "  Current Users: ${GITHUB_USER:-not set}"
    echo ""
    echo "To protect a service, add these annotations to its ingress:"
    echo '  nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.auth-system.svc.cluster.local:4180/oauth2/auth"'
    echo '  nginx.ingress.kubernetes.io/auth-signin: "https://'${DOMAIN}'/oauth2/start?rd=$scheme://$host$escaped_request_uri"'
    echo '  nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Access-Token"'
}

uninstall_auth() {
    info "Uninstalling Centralized Authentication..."
    
    kubectl delete ingress oauth2-proxy -n ${COMPONENT_NAMESPACE} --ignore-not-found
    kubectl delete service oauth2-proxy -n ${COMPONENT_NAMESPACE} --ignore-not-found
    kubectl delete deployment oauth2-proxy -n ${COMPONENT_NAMESPACE} --ignore-not-found
    kubectl delete configmap oauth2-proxy-config -n ${COMPONENT_NAMESPACE} --ignore-not-found
    kubectl delete secret oauth2-proxy-secret -n ${COMPONENT_NAMESPACE} --ignore-not-found
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "Centralized Authentication uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_auth
        ;;
    uninstall)
        uninstall_auth
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac