#!/bin/bash
set -euo pipefail

# Kubernetes Dashboard Component Installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="k8s-dashboard"
COMPONENT_NAMESPACE="kubernetes-dashboard"

install_k8s_dashboard() {
    info "Installing Kubernetes Dashboard..."
    
    # Deploy Kubernetes Dashboard
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v3.0.0-alpha0/charts/kubernetes-dashboard.yaml
    
    # Wait for deployment
    info "Waiting for Kubernetes Dashboard deployment..."
    kubectl rollout status deployment/kubernetes-dashboard -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Create admin user and role binding
    info "Creating admin user..."
    kubectl apply -f "${SCRIPT_DIR}/dashboard-admin-user.yaml"
    
    # Deploy ingress with OAuth2 authentication
    if [[ -n "${DOMAIN:-}" ]]; then
        info "Deploying Dashboard ingress with OAuth2 authentication..."
        envsubst < "${SCRIPT_DIR}/dashboard-ingress.yaml" | kubectl apply -f -
    fi
    
    # Get token for admin user
    SECRET=$(kubectl get secret -n ${COMPONENT_NAMESPACE} | grep admin-user-token | awk '{print $1}')
    TOKEN=$(kubectl get secret -n ${COMPONENT_NAMESPACE} $SECRET -o jsonpath='{.data.token}' | base64 -d)
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/k8s-dashboard.conf" <<EOF
DASHBOARD_TOKEN=$TOKEN
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/k8s-dashboard.conf"
    
    success "Kubernetes Dashboard installed successfully!"
    
    # Display access information
    info "Dashboard Access Information:"
    if [[ -n "${DOMAIN:-}" ]]; then
        echo "  URL: https://dashboard.${DOMAIN}"
        echo ""
        echo "Access is controlled by OAuth2. Once authenticated, use the token from:"
        echo "  ${SCRIPT_DIR}/../../.cluster/credentials/k8s-dashboard.conf"
    else
        echo "  Port-forward: kubectl port-forward -n ${COMPONENT_NAMESPACE} svc/kubernetes-dashboard 8443:443"
        echo "  URL: https://localhost:8443"
        echo ""
        echo "Token saved to: ${SCRIPT_DIR}/../../.cluster/credentials/k8s-dashboard.conf"
    fi
}

uninstall_k8s_dashboard() {
    info "Uninstalling Kubernetes Dashboard..."
    
    kubectl delete ingress kubernetes-dashboard -n ${COMPONENT_NAMESPACE} --ignore-not-found
    kubectl delete -f https://raw.githubusercontent.com/kubernetes/dashboard/v3.0.0-alpha0/charts/kubernetes-dashboard.yaml --ignore-not-found
    kubectl delete -f "${SCRIPT_DIR}/dashboard-admin-user.yaml" --ignore-not-found
    
    success "Kubernetes Dashboard uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_k8s_dashboard
        ;;
    uninstall)
        uninstall_k8s_dashboard
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac