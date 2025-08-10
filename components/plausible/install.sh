#!/bin/bash
set -euo pipefail

# Plausible Analytics Component Installation
# Privacy-focused web analytics

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="plausible"
COMPONENT_NAMESPACE="plausible"

install_plausible() {
    info "Installing Plausible Analytics..."
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for Plausible installation"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate secrets
    SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')
    POSTGRES_PASSWORD=$(generate_password)
    CLICKHOUSE_PASSWORD=$(generate_password)
    ADMIN_PASSWORD=$(generate_password)
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/plausible.conf" <<EOF
PLAUSIBLE_URL=https://analytics.${DOMAIN}
ADMIN_EMAIL=admin@${DOMAIN}
ADMIN_PASSWORD=$ADMIN_PASSWORD
SECRET_KEY_BASE=$SECRET_KEY_BASE
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
CLICKHOUSE_PASSWORD=$CLICKHOUSE_PASSWORD

# Tracking Script Integration
# Add this to your website's <head> tag:
<script defer data-domain="yourdomain.com" src="https://analytics.${DOMAIN}/js/script.js"></script>

# Or use the tagged-events script for custom events:
<script defer data-domain="yourdomain.com" src="https://analytics.${DOMAIN}/js/script.tagged-events.js"></script>

# Custom Events Example:
plausible('Download', {props: {file: 'report.pdf'}})
plausible('Signup', {props: {plan: 'premium'}})

# API Access
# Generate API key in Settings -> API keys
# Example API call:
# curl -H "Authorization: Bearer YOUR_API_KEY" \\
#   "https://analytics.${DOMAIN}/api/v1/stats/aggregate?site_id=yourdomain.com&metrics=visitors,pageviews"
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/plausible.conf"
    
    # Create secrets
    kubectl create secret generic plausible-secrets \
        --namespace=${COMPONENT_NAMESPACE} \
        --from-literal=secret-key-base="${SECRET_KEY_BASE}" \
        --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
        --from-literal=clickhouse-password="${CLICKHOUSE_PASSWORD}" \
        --from-literal=admin-password="${ADMIN_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy PostgreSQL
    info "Deploying PostgreSQL for Plausible..."
    kubectl apply -f "${SCRIPT_DIR}/plausible-postgres-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/plausible-postgres-service.yaml"
    
    # Deploy ClickHouse
    info "Deploying ClickHouse for analytics data..."
    kubectl apply -f "${SCRIPT_DIR}/plausible-clickhouse-config.yaml"
    kubectl apply -f "${SCRIPT_DIR}/plausible-clickhouse-deployment.yaml"
    kubectl apply -f "${SCRIPT_DIR}/plausible-clickhouse-service.yaml"
    
    # Wait for dependencies
    kubectl wait --for=condition=ready pod -l app=plausible-postgres -n ${COMPONENT_NAMESPACE} --timeout=300s
    kubectl wait --for=condition=ready pod -l app=plausible-clickhouse -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Deploy Plausible
    info "Deploying Plausible Analytics..."
    envsubst < "${SCRIPT_DIR}/plausible-deployment.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/plausible-service.yaml"
    envsubst < "${SCRIPT_DIR}/plausible-ingress.yaml" | kubectl apply -f -
    
    # Wait for deployment
    info "Waiting for Plausible deployment..."
    kubectl rollout status deployment/plausible -n ${COMPONENT_NAMESPACE} --timeout=600s
    
    # Create admin user
    info "Creating admin user..."
    sleep 30  # Give Plausible time to fully initialize
    
    kubectl exec -n ${COMPONENT_NAMESPACE} deployment/plausible -- /app/bin/plausible eval "
      user = %Plausible.Auth.User{
        email: \"admin@${DOMAIN}\",
        password: \"${ADMIN_PASSWORD}\",
        password_confirmation: \"${ADMIN_PASSWORD}\",
        email_verified: true
      }
      {:ok, user} = Plausible.Auth.User.new(user) |> Plausible.Repo.insert()
      Plausible.Billing.Quota.Usage.ensure_feature_access(user, :sites_limit, 50)
      Plausible.Billing.Quota.Usage.ensure_feature_access(user, :team_members_limit, 10)
      Plausible.Billing.Quota.Usage.ensure_feature_access(user, :stats_api, true)
    " || true
    
    success "Plausible Analytics installed successfully!"
    
    # Display access information
    info "Plausible Analytics Access Information:"
    echo "  URL: https://analytics.${DOMAIN}"
    echo "  Admin Email: admin@${DOMAIN}"
    echo "  Admin Password: Saved in credentials file"
    echo ""
    echo "Quick Start:"
    echo "  1. Login with admin credentials"
    echo "  2. Add your first website"
    echo "  3. Add tracking script to your site:"
    echo '     <script defer data-domain="yourdomain.com" src="https://analytics.'${DOMAIN}'/js/script.js"></script>'
    echo ""
    echo "Features:"
    echo "  ✓ Privacy-focused (no cookies, GDPR compliant)"
    echo "  ✓ Lightweight tracking script (<1KB)"
    echo "  ✓ Real-time analytics"
    echo "  ✓ Custom events tracking"
    echo "  ✓ API access"
    echo "  ✓ Email reports"
    echo "  ✓ Google Search Console integration"
    echo "  ✓ Multiple sites support"
    echo ""
    echo "Script Variants:"
    echo "  - script.js: Standard tracking"
    echo "  - script.tagged-events.js: Custom events support"
    echo "  - script.outbound-links.js: External link tracking"
    echo "  - script.file-downloads.js: Download tracking"
    echo "  - script.hash.js: Hash-based routing support"
    echo "  - script.exclusions.js: Exclude internal traffic"
    echo ""
    echo "Credentials saved to: ${SCRIPT_DIR}/../../.cluster/credentials/plausible.conf"
}

uninstall_plausible() {
    info "Uninstalling Plausible Analytics..."
    
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "Plausible Analytics uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_plausible
        ;;
    uninstall)
        uninstall_plausible
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac