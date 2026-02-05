#!/bin/bash
set -euo pipefail

# Moodle LMS Installation
# Learning management system for LTI integration testing

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

    # Add Bitnami Helm repo
    info "Adding Bitnami Helm repository..."
    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo update

    # Create temporary values file with passwords
    cat > /tmp/moodle-install-values.yaml <<EOF
moodlePassword: "${MOODLE_PASSWORD}"
postgresql:
  auth:
    password: "${POSTGRES_PASSWORD}"
    postgresPassword: "${POSTGRES_PASSWORD}"
EOF

    # Merge with main values file
    info "Installing Moodle via Helm..."
    helm upgrade --install moodle bitnami/moodle \
        -f "${SCRIPT_DIR}/values.yaml" \
        -f /tmp/moodle-install-values.yaml \
        -n "${COMPONENT_NAMESPACE}" \
        --wait \
        --timeout 15m

    # Clean up temp file
    rm -f /tmp/moodle-install-values.yaml

    # Create ingress
    info "Creating Moodle ingress..."
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: moodle-ingress
  namespace: ${COMPONENT_NAMESPACE}
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - moodle.${DOMAIN}
    secretName: moodle-tls
  rules:
  - host: moodle.${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: moodle
            port:
              number: 80
EOF

    # Wait for ingress to be ready
    info "Waiting for TLS certificate..."
    sleep 10

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

    helm uninstall moodle -n ${COMPONENT_NAMESPACE} --ignore-not-found || true
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found

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
