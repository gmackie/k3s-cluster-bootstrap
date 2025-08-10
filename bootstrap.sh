#!/bin/bash
set -euo pipefail

# K3s Cluster Bootstrap Script
# Modular deployment system for k3s clusters

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Default values
ENVIRONMENT="local"
COMPONENTS=""
DOMAIN=""
NODE_TYPE="master"
HETZNER_API_TOKEN="${HETZNER_API_TOKEN:-}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --components)
            COMPONENTS="$2"
            shift 2
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --node-type)
            NODE_TYPE="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate environment
if [[ "$ENVIRONMENT" != "local" && "$ENVIRONMENT" != "hetzner" ]]; then
    error "Invalid environment: $ENVIRONMENT. Must be 'local' or 'hetzner'"
fi

# Validate Hetzner requirements
if [[ "$ENVIRONMENT" == "hetzner" && -z "$HETZNER_API_TOKEN" ]]; then
    error "HETZNER_API_TOKEN environment variable is required for Hetzner deployment"
fi

# Parse components
IFS=',' read -ra COMPONENT_ARRAY <<< "$COMPONENTS"
if [[ "$COMPONENTS" == "all" ]]; then
    COMPONENT_ARRAY=("base" "storage" "longhorn" "secrets" "auth" "authentik" "monitoring" "registry" "npm-registry" "gitea" "drone" "argocd" "k8s-dashboard" "vaultwarden" "minio" "nextcloud" "sentry" "plausible" "matrix" "mastodon" "mumble" "jupyterhub" "control-panel" "backup")
fi

# Main execution
info "Starting K3s cluster bootstrap"
info "Environment: $ENVIRONMENT"
info "Components: ${COMPONENT_ARRAY[*]}"
info "Domain: ${DOMAIN:-Not specified}"

# Run environment-specific setup
case $ENVIRONMENT in
    local)
        source "${SCRIPT_DIR}/environments/local/setup.sh"
        ;;
    hetzner)
        source "${SCRIPT_DIR}/environments/hetzner/setup.sh"
        ;;
esac

# Install components in order
for component in "${COMPONENT_ARRAY[@]}"; do
    info "Installing component: $component"
    
    if [[ -f "${SCRIPT_DIR}/components/${component}/install.sh" ]]; then
        source "${SCRIPT_DIR}/components/${component}/install.sh"
    else
        error "Component script not found: $component"
    fi
done

info "Bootstrap complete!"
info "Access your cluster:"
if [[ -n "$DOMAIN" ]]; then
    info "  Control Panel: https://$DOMAIN"
    info "  Gitea: https://$DOMAIN/git"
    info "  Grafana: https://$DOMAIN/grafana"
else
    info "  Use kubectl to manage your cluster"
fi