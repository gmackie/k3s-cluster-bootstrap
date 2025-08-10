#!/bin/bash
set -euo pipefail

# K3s Cluster Bootstrap Script
# Modular deployment system for k3s clusters

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Load environment file if exists
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    info "Loading configuration from .env file"
    source "${SCRIPT_DIR}/.env"
fi

# Default values (after loading .env)
ENVIRONMENT="${ENVIRONMENT:-local}"
COMPONENTS="${COMPONENTS:-}"
DOMAIN="${DOMAIN:-}"
NODE_TYPE="${NODE_TYPE:-master}"
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
if [[ "$ENVIRONMENT" != "local" && "$ENVIRONMENT" != "hetzner" && "$ENVIRONMENT" != "vps" ]]; then
    error "Invalid environment: $ENVIRONMENT. Must be 'local', 'hetzner', or 'vps'"
fi

# Validate Hetzner requirements
if [[ "$ENVIRONMENT" == "hetzner" && -z "$HETZNER_API_TOKEN" ]]; then
    error "HETZNER_API_TOKEN environment variable is required for Hetzner deployment"
fi

# Validate VPS requirements
if [[ "$ENVIRONMENT" == "vps" && -z "$SERVER_IP" ]]; then
    error "SERVER_IP environment variable is required for VPS deployment"
fi

# Validate domain if provided
if [[ -n "$DOMAIN" ]]; then
    info "Using domain: $DOMAIN"
else
    warn "No domain specified. Some features may not be available."
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
info "Setting up $ENVIRONMENT environment"
case $ENVIRONMENT in
    local)
        source "${SCRIPT_DIR}/environments/local/setup.sh"
        ;;
    hetzner)
        source "${SCRIPT_DIR}/environments/hetzner/setup.sh"
        ;;
    vps)
        # For VPS, we assume K3s is already installed or will be installed manually
        info "VPS deployment: Ensure K3s is installed on $SERVER_IP"
        ;;
esac

# Install components in order
info "Installing ${#COMPONENT_ARRAY[@]} components"
for component in "${COMPONENT_ARRAY[@]}"; do
    info "Installing component: $component"
    
    if [[ -f "${SCRIPT_DIR}/components/${component}/install.sh" ]]; then
        # Export common variables for component scripts
        export DOMAIN ENVIRONMENT ADMIN_EMAIL DEFAULT_STORAGE_CLASS
        export GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET GITHUB_ORG
        export SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_PASSWORD SMTP_USE_TLS SMTP_FROM
        
        source "${SCRIPT_DIR}/components/${component}/install.sh"
        success "Component $component installed successfully"
    else
        error "Component script not found: $component"
    fi
done

# Run control panel configuration if installed
if [[ " ${COMPONENT_ARRAY[@]} " =~ " control-panel " ]]; then
    info "Configuring control panel with discovered services"
    if [[ -f "${SCRIPT_DIR}/components/control-panel/generate-config.sh" ]]; then
        bash "${SCRIPT_DIR}/components/control-panel/generate-config.sh"
    fi
fi

success "\n🎉 Bootstrap complete!"
info "\nAccess your services:"
if [[ -n "$DOMAIN" ]]; then
    if [[ " ${COMPONENT_ARRAY[@]} " =~ " control-panel " ]]; then
        info "  🏠 Control Panel: https://$DOMAIN"
    fi
    if [[ " ${COMPONENT_ARRAY[@]} " =~ " gitea " ]]; then
        info "  📦 Git Repository: https://git.$DOMAIN"
    fi
    if [[ " ${COMPONENT_ARRAY[@]} " =~ " monitoring " ]]; then
        info "  📊 Monitoring: https://metrics.$DOMAIN"
    fi
    if [[ " ${COMPONENT_ARRAY[@]} " =~ " registry " ]]; then
        info "  🐳 Container Registry: https://registry.$DOMAIN"
    fi
    if [[ " ${COMPONENT_ARRAY[@]} " =~ " argocd " ]]; then
        info "  🔄 ArgoCD: https://argocd.$DOMAIN"
    fi
    if [[ " ${COMPONENT_ARRAY[@]} " =~ " notebook " ]] || [[ " ${COMPONENT_ARRAY[@]} " =~ " jupyterhub " ]]; then
        info "  📓 JupyterHub: https://notebook.$DOMAIN"
    fi
    echo ""
    info "Login with your GitHub account (org: ${GITHUB_ORG:-any})"
else
    info "  Use kubectl to manage your cluster"
fi

if [[ -d ".cluster/credentials" ]]; then
    echo ""
    warn "Important: Credentials saved in .cluster/credentials/"
    warn "Keep these files secure and backed up!"
fi