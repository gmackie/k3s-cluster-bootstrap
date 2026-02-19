#!/bin/bash
set -euo pipefail

# K3s Cluster Bootstrap Script v3 - Interactive Setup with OAuth Wizard
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# Load common functions
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/.cluster-state.sh"

# Default values
ENVIRONMENT="${ENVIRONMENT:-hetzner}"
COMPONENTS="${COMPONENTS:-}"
DOMAIN="${DOMAIN:-}"
NODE_TYPE="${NODE_TYPE:-master}"
RESUME="${RESUME:-false}"
SKIP_CONFIRM="${SKIP_CONFIRM:-false}"
INTERACTIVE="${INTERACTIVE:-true}"

# Colors for interactive mode
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Component dependencies (simple function instead of associative array)
get_component_deps() {
    local component=$1
    case $component in
        auth) echo "base" ;;
        monitoring) echo "base,storage" ;;
        registry) echo "base,storage" ;;
        gitea) echo "base,storage" ;;
        argocd) echo "base" ;;
        control-panel) echo "base" ;;
        landing-page) echo "base,auth" ;;
        *) echo "" ;;
    esac
}

# Interactive banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║     K3s Cluster Bootstrap System v3                          ║"
    echo "║     Interactive Setup with GitHub OAuth                       ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

# Interactive domain setup
setup_domain() {
    echo -e "${BLUE}═══ Domain Configuration ═══${NC}"
    echo
    if [[ -z "$DOMAIN" ]]; then
        echo -e "${YELLOW}Enter your domain name (e.g., example.com):${NC}"
        read -p "> " DOMAIN
        while [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; do
            echo -e "${RED}Invalid domain format. Please enter a valid domain:${NC}"
            read -p "> " DOMAIN
        done
    fi
    echo -e "${GREEN}✓ Domain set to: $DOMAIN${NC}"
    echo
    save_credential "DOMAIN" "$DOMAIN"
}

# Interactive GitHub OAuth setup
setup_github_oauth() {
    echo -e "${BLUE}═══ GitHub OAuth Configuration ═══${NC}"
    echo
    echo -e "${YELLOW}Setting up GitHub OAuth for secure authentication${NC}"
    echo
    
    # Check if we already have OAuth credentials
    local existing_client_id=$(get_credential "GITHUB_CLIENT_ID")
    local existing_client_secret=$(get_credential "GITHUB_CLIENT_SECRET")
    
    if [[ -n "$existing_client_id" ]] && [[ -n "$existing_client_secret" ]]; then
        echo -e "${GREEN}✓ Found existing GitHub OAuth credentials${NC}"
        echo -e "  Client ID: ${existing_client_id:0:10}..."
        echo
        echo -e "${YELLOW}Use existing credentials? (Y/n):${NC}"
        read -p "> " use_existing
        if [[ "${use_existing,,}" != "n" ]]; then
            GITHUB_CLIENT_ID="$existing_client_id"
            GITHUB_CLIENT_SECRET="$existing_client_secret"
            return
        fi
    fi
    
    echo -e "${PURPLE}To create a GitHub OAuth App:${NC}"
    echo "1. Go to https://github.com/settings/applications/new"
    echo "2. Fill in the following details:"
    echo -e "   ${CYAN}Application name:${NC} $DOMAIN Infrastructure"
    echo -e "   ${CYAN}Homepage URL:${NC} https://$DOMAIN"
    echo -e "   ${CYAN}Authorization callback URL:${NC} https://$DOMAIN/oauth2/callback"
    echo "3. Click 'Register application'"
    echo "4. Copy the Client ID and Client Secret"
    echo
    
    echo -e "${YELLOW}Enter your GitHub OAuth Client ID:${NC}"
    read -p "> " GITHUB_CLIENT_ID
    while [[ -z "$GITHUB_CLIENT_ID" ]]; do
        echo -e "${RED}Client ID cannot be empty:${NC}"
        read -p "> " GITHUB_CLIENT_ID
    done
    
    echo -e "${YELLOW}Enter your GitHub OAuth Client Secret:${NC}"
    read -s -p "> " GITHUB_CLIENT_SECRET
    echo
    while [[ -z "$GITHUB_CLIENT_SECRET" ]]; do
        echo -e "${RED}Client Secret cannot be empty:${NC}"
        read -s -p "> " GITHUB_CLIENT_SECRET
        echo
    done
    
    # Save credentials
    save_credential "GITHUB_CLIENT_ID" "$GITHUB_CLIENT_ID"
    save_credential "GITHUB_CLIENT_SECRET" "$GITHUB_CLIENT_SECRET"
    
    echo -e "${GREEN}✓ OAuth credentials saved${NC}"
    echo
}

# Interactive service selection
select_services() {
    echo -e "${BLUE}═══ Service Selection ═══${NC}"
    echo
    echo -e "${YELLOW}Select services to install:${NC}"
    echo
    
    local services=(
        "base:Core K3s with ingress and SSL certificates:true"
        "storage:Storage provisioning (local-path):true"
        "landing-page:Custom landing page for $DOMAIN:true"
        "auth:GitHub OAuth authentication:true"
        "sealed-secrets:Secrets management for GitOps:true"
        "monitoring:Prometheus, Grafana, Alertmanager:false"
        "registry:Docker Registry with UI:false"
        "gitea:Git repository hosting:false"
        "argocd:GitOps continuous deployment:false"
        "k8s-dashboard:Kubernetes dashboard:false"
        "control-panel:Central control panel:true"
    )
    
    local selected_services=()
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name service_desc default_selected <<< "$service_info"
        
        local prompt_text="Install ${service_desc}?"
        if [[ "$default_selected" == "true" ]]; then
            prompt_text="$prompt_text (Y/n)"
            echo -e "${CYAN}$prompt_text:${NC}"
            read -p "> " install_choice
            if [[ "${install_choice,,}" != "n" ]]; then
                selected_services+=("$service_name")
                echo -e "${GREEN}  ✓ $service_name will be installed${NC}"
            else
                echo -e "${YELLOW}  ✗ $service_name skipped${NC}"
            fi
        else
            prompt_text="$prompt_text (y/N)"
            echo -e "${CYAN}$prompt_text:${NC}"
            read -p "> " install_choice
            if [[ "${install_choice,,}" == "y" ]]; then
                selected_services+=("$service_name")
                echo -e "${GREEN}  ✓ $service_name will be installed${NC}"
            else
                echo -e "${YELLOW}  ✗ $service_name skipped${NC}"
            fi
        fi
    done
    
    echo
    COMPONENTS=$(IFS=,; echo "${selected_services[*]}")
    echo -e "${GREEN}Selected services: $COMPONENTS${NC}"
    echo
}

# Deploy landing page with domain substitution
deploy_landing_page() {
    info "Deploying landing page for $DOMAIN..."
    
    local domain_name="${DOMAIN}"
    
    # Create temporary file with substituted values
    local temp_file="/tmp/landing-page-${domain_name}.yaml"
    
    # Substitute variables in template
    sed -e "s/\${DOMAIN_NAME}/${domain_name}/g" \
        "${SCRIPT_DIR}/landing-page-template.yaml" > "$temp_file"
    
    # Apply the landing page
    kubectl apply -f "$temp_file"
    
    # Clean up
    rm -f "$temp_file"
    
    success "Landing page deployed for $domain_name"
}

# Install landing page component
install_landing_page() {
    local component="landing-page"
    
    if is_component_installed "$component"; then
        info "Landing page already installed"
        return 0
    fi
    
    if ! wait_for_ingress; then
        error "Ingress controller not ready"
        return 1
    fi
    
    if ! check_component_deps "$component"; then
        error "Dependencies not met for $component"
        return 1
    fi
    
    # Deploy the landing page
    deploy_landing_page
    
    # Wait for deployment
    kubectl rollout status deployment/landing-page -n control-panel --timeout=300s
    
    save_component_state "$component" "installed"
    success "Landing page installation complete"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --components)
            COMPONENTS="$2"
            INTERACTIVE="false"
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
        --resume)
            RESUME="true"
            INTERACTIVE="false"
            shift
            ;;
        --skip-confirm)
            SKIP_CONFIRM="true"
            shift
            ;;
        --non-interactive)
            INTERACTIVE="false"
            shift
            ;;
        --reset)
            rm -rf "${SCRIPT_DIR}/.cluster"
            info "Cluster state reset"
            exit 0
            ;;
        --status)
            info "Installed components:"
            list_installed_components
            info "Bootstrap phase: $(get_bootstrap_phase)"
            exit 0
            ;;
        --help)
            show_help_v3
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

show_help_v3() {
    cat << EOF
K3s Cluster Bootstrap System v3 - Interactive Setup

Usage: ./bootstrap-v3.sh [OPTIONS]

Options:
    --environment <local|hetzner|vps>   Deployment environment (default: hetzner)
    --components <list>                 Comma-separated list of components (disables interactive mode)
    --domain <domain>                   Domain name for the cluster
    --node-type <master|agent>          Node type for multi-node setup (default: master)
    --resume                            Resume from last failed component
    --skip-confirm                      Skip confirmation prompts
    --non-interactive                   Disable interactive mode
    --reset                             Reset cluster state
    --status                            Show cluster status
    --help                              Show this help message

Components:
    base            - K3s base installation with ingress and cert-manager
    storage         - Storage class configuration (local-path or longhorn)
    landing-page    - Custom landing page with domain branding
    auth            - OAuth2 authentication system
    sealed-secrets  - Secrets management for GitOps
    monitoring      - Prometheus, Grafana, Alertmanager stack
    registry        - Docker Registry with UI
    gitea           - Git repository hosting
    argocd          - GitOps continuous deployment
    k8s-dashboard   - Kubernetes dashboard
    control-panel   - Central control panel
    
Interactive Mode (default):
    The script will guide you through:
    1. Domain configuration
    2. GitHub OAuth app setup
    3. Service selection
    4. Installation progress
    
Examples:
    # Interactive setup (recommended)
    ./bootstrap-v3.sh
    
    # Non-interactive with all components
    ./bootstrap-v3.sh --domain gmac.io --components all --non-interactive
    
    # Resume failed installation
    ./bootstrap-v3.sh --resume
EOF
}

# Load or initialize state
initialize_state() {
    init_state
    
    if [[ "$RESUME" == "true" ]]; then
        info "Resuming installation..."
        load_environment_config
        
        # Load saved credentials
        GITHUB_CLIENT_ID=$(get_credential "GITHUB_CLIENT_ID")
        GITHUB_CLIENT_SECRET=$(get_credential "GITHUB_CLIENT_SECRET")
        DOMAIN=$(get_credential "DOMAIN")
        
        info "Loaded configuration:"
        info "  Environment: $ENVIRONMENT"
        info "  Domain: $DOMAIN"
        info "  Installed components: $(list_installed_components | tr '\n' ' ')"
    else
        save_environment_config
    fi
}

# Main installation flow
main() {
    # Show banner in interactive mode
    if [[ "$INTERACTIVE" == "true" ]]; then
        show_banner
    fi
    
    # Initialize state
    initialize_state
    
    # Interactive setup if enabled
    if [[ "$INTERACTIVE" == "true" ]] && [[ "$RESUME" != "true" ]]; then
        setup_domain
        
        # Check if auth component will be installed
        echo -e "${YELLOW}Will you be installing authentication? (Y/n):${NC}"
        read -p "> " install_auth
        if [[ "${install_auth,,}" != "n" ]]; then
            setup_github_oauth
        fi
        
        select_services
        
        # Confirmation
        echo -e "${BLUE}═══ Installation Summary ═══${NC}"
        echo -e "${CYAN}Domain:${NC} $DOMAIN"
        echo -e "${CYAN}Environment:${NC} $ENVIRONMENT"
        echo -e "${CYAN}Services:${NC} $COMPONENTS"
        echo
        echo -e "${YELLOW}Proceed with installation? (Y/n):${NC}"
        read -p "> " confirm
        if [[ "${confirm,,}" == "n" ]]; then
            echo -e "${RED}Installation cancelled${NC}"
            exit 0
        fi
    fi
    
    # Export OAuth credentials if available
    if [[ -n "${GITHUB_CLIENT_ID:-}" ]]; then
        export GITHUB_CLIENT_ID
        export GITHUB_CLIENT_SECRET
    fi
    
    # Export domain for use in scripts
    export DOMAIN_NAME="$DOMAIN"
    
    # Now run the installation
    run_installation
}

# Component installation functions (extend bootstrap-v2.sh)
install_component() {
    local component=$1
    
    case $component in
        landing-page)
            install_landing_page
            ;;
        *)
            # Call the original install_component from bootstrap-v2.sh
            install_component_v2 "$component"
            ;;
    esac
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi