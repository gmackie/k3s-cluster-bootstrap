#!/bin/bash
set -euo pipefail

# K3s Cluster Bootstrap Script v2 - Resumable and Robust
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
        *) echo "" ;;
    esac
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
            shift
            ;;
        --skip-confirm)
            SKIP_CONFIRM="true"
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
            show_help_v2
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

show_help_v2() {
    cat << EOF
K3s Cluster Bootstrap System v2

Usage: ./bootstrap-v2.sh [OPTIONS]

Options:
    --environment <local|hetzner|vps>   Deployment environment (default: hetzner)
    --components <list>                 Comma-separated list of components or 'all'
    --domain <domain>                   Domain name for the cluster
    --node-type <master|agent>          Node type for multi-node setup (default: master)
    --resume                            Resume from last failed component
    --skip-confirm                      Skip confirmation prompts
    --reset                             Reset cluster state
    --status                            Show cluster status
    --help                              Show this help message

Components:
    base            - K3s base installation with ingress and cert-manager
    storage         - Storage class configuration (local-path or longhorn)
    longhorn        - Longhorn distributed storage
    auth            - OAuth2 authentication system
    monitoring      - Prometheus, Grafana, Alertmanager stack
    registry        - Harbor container registry
    gitea           - Git repository with CI/CD
    argocd          - GitOps continuous deployment
    k8s-dashboard   - Kubernetes dashboard
    control-panel   - Central control panel
    
Environment Variables:
    KUBECONFIG              Path to kubeconfig file
    HETZNER_API_TOKEN       Required for Hetzner deployments
    GITHUB_CLIENT_ID        GitHub OAuth client ID (for auth component)
    GITHUB_CLIENT_SECRET    GitHub OAuth client secret
    
Examples:
    # Fresh install with all components
    ./bootstrap-v2.sh --environment hetzner --components all --domain gmac.io
    
    # Resume failed installation
    ./bootstrap-v2.sh --resume
    
    # Install specific components
    ./bootstrap-v2.sh --components base,auth,gitea,registry --domain gmac.io
EOF
}

# Validate environment
validate_environment() {
    case $ENVIRONMENT in
        local|hetzner|vps)
            ;;
        *)
            error "Invalid environment: $ENVIRONMENT"
            ;;
    esac
    
    # Check environment-specific requirements
    if [[ "$ENVIRONMENT" == "hetzner" ]]; then
        if [[ -z "${HETZNER_API_TOKEN:-}" ]] && [[ ! -f ~/.hcloud/config.toml ]]; then
            error "HETZNER_API_TOKEN required for Hetzner deployment"
        fi
    fi
    
    # Set KUBECONFIG based on environment
    if [[ -z "${KUBECONFIG:-}" ]]; then
        case $ENVIRONMENT in
            local)
                export KUBECONFIG="${HOME}/.kube/config"
                ;;
            hetzner)
                export KUBECONFIG="${HOME}/.kube/config-hetzner"
                ;;
            vps)
                export KUBECONFIG="${HOME}/.kube/config-vps"
                ;;
        esac
    fi
    
    # Validate domain
    if [[ -z "$DOMAIN" ]] && [[ "$COMPONENTS" != "" ]]; then
        error "Domain is required for component installation"
    fi
}

# Load or initialize state
initialize_state() {
    init_state
    
    if [[ "$RESUME" == "true" ]]; then
        info "Resuming installation..."
        load_environment_config
        
        # Override with command line args if provided
        ENVIRONMENT="${1:-$ENVIRONMENT}"
        DOMAIN="${2:-$DOMAIN}"
        
        info "Loaded configuration:"
        info "  Environment: $ENVIRONMENT"
        info "  Domain: $DOMAIN"
        info "  Installed components: $(list_installed_components | tr '\n' ' ')"
    else
        save_environment_config
    fi
}

# Parse and validate components
parse_components() {
    if [[ -z "$COMPONENTS" ]] && [[ "$RESUME" == "true" ]]; then
        # Resume mode - determine remaining components
        local installed=($(list_installed_components))
        local all_components=(base storage auth monitoring registry gitea argocd k8s-dashboard control-panel)
        COMPONENT_ARRAY=()
        
        for comp in "${all_components[@]}"; do
            if ! is_component_installed "$comp"; then
                COMPONENT_ARRAY+=("$comp")
            fi
        done
        
        if [[ ${#COMPONENT_ARRAY[@]} -eq 0 ]]; then
            success "All components are already installed!"
            exit 0
        fi
        
        info "Remaining components to install: ${COMPONENT_ARRAY[*]}"
    else
        # Normal mode - parse component list
        if [[ "$COMPONENTS" == "all" ]]; then
            COMPONENT_ARRAY=(base storage auth monitoring registry gitea argocd k8s-dashboard control-panel)
        else
            IFS=',' read -ra COMPONENT_ARRAY <<< "$COMPONENTS"
        fi
    fi
}

# Check component dependencies
check_dependencies() {
    local component=$1
    local deps=$(get_component_deps "$component")
    
    if [[ -n "$deps" ]]; then
        IFS=',' read -ra dep_array <<< "$deps"
        for dep in "${dep_array[@]}"; do
            if ! is_component_installed "$dep"; then
                error "Component '$component' requires '$dep' to be installed first"
            fi
        done
    fi
}

# Install a component
install_component() {
    local component=$1
    
    # Skip if already installed
    if is_component_installed "$component"; then
        info "Component '$component' is already installed, skipping..."
        return 0
    fi
    
    # Check dependencies
    check_dependencies "$component"
    
    # Mark as in progress
    save_component_state "$component" "in_progress"
    
    info "Installing component: $component"
    
    # Set up environment for component script
    export DOMAIN ENVIRONMENT NODE_TYPE SCRIPT_DIR
    export KUBECONFIG="${KUBECONFIG}"
    export STORAGE_CLASS="${STORAGE_CLASS:-longhorn}"
    export ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${DOMAIN}}"
    
    # Component-specific variables
    export GITHUB_CLIENT_ID="${GITHUB_CLIENT_ID:-}"
    export GITHUB_CLIENT_SECRET="${GITHUB_CLIENT_SECRET:-}"
    export GITHUB_ORG="${GITHUB_ORG:-}"
    export GITHUB_USER="${GITHUB_USER:-}"
    
    # Run component installation
    local component_script="${SCRIPT_DIR}/components/${component}/install.sh"
    if [[ -f "$component_script" ]]; then
        if bash "$component_script"; then
            save_component_state "$component" "completed"
            success "Component '$component' installed successfully"
        else
            save_component_state "$component" "failed"
            error "Failed to install component '$component'"
        fi
    else
        error "Component script not found: $component_script"
    fi
}

# Main execution
main() {
    info "K3s Cluster Bootstrap v2"
    
    # Validate environment
    validate_environment
    
    # Initialize state
    initialize_state "$ENVIRONMENT" "$DOMAIN"
    
    # Parse components
    parse_components
    
    # Show plan
    if [[ "$SKIP_CONFIRM" != "true" ]] && [[ ${#COMPONENT_ARRAY[@]} -gt 0 ]]; then
        info "Installation plan:"
        info "  Environment: $ENVIRONMENT"
        info "  Domain: $DOMAIN"
        info "  Components: ${COMPONENT_ARRAY[*]}"
        echo
        read -p "Continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Check if k3s is installed
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found. Please ensure k3s is installed and kubeconfig is set"
    fi
    
    # Test cluster connection
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster. Check your kubeconfig: $KUBECONFIG"
    fi
    
    # Install components
    for component in "${COMPONENT_ARRAY[@]}"; do
        install_component "$component"
    done
    
    # Update control panel if installed
    if is_component_installed "control-panel"; then
        info "Updating control panel configuration..."
        if [[ -f "${SCRIPT_DIR}/components/control-panel/generate-config.sh" ]]; then
            bash "${SCRIPT_DIR}/components/control-panel/generate-config.sh"
        fi
    fi
    
    # Show summary
    success "Bootstrap complete!"
    info "Installed components: $(list_installed_components | tr '\n' ' ')"
    
    if [[ -n "$DOMAIN" ]]; then
        info ""
        info "Access your services:"
        is_component_installed "control-panel" && info "  🏠 Control Panel: https://${DOMAIN}"
        is_component_installed "gitea" && info "  📦 Git Repository: https://git.${DOMAIN}"
        is_component_installed "registry" && info "  🐳 Container Registry: https://registry.${DOMAIN}"
        is_component_installed "monitoring" && info "  📊 Grafana: https://grafana.${DOMAIN}"
        is_component_installed "argocd" && info "  🔄 ArgoCD: https://argocd.${DOMAIN}"
        is_component_installed "k8s-dashboard" && info "  ☸️  Dashboard: https://dashboard.${DOMAIN}"
    fi
    
    # Show credentials location
    if [[ -d "${SCRIPT_DIR}/.cluster/credentials" ]]; then
        info ""
        info "Credentials saved in: ${SCRIPT_DIR}/.cluster/credentials/"
    fi
}

# Make functions available for v3
install_component_v2() {
    install_component "$@"
}

validate_environment_v2() {
    validate_environment "$@"
}

# Run main only if not being sourced and --skip-main not set
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "$1" != "--skip-main" ]]; then
    main "$@"
fi