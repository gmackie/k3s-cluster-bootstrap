#!/bin/bash
set -euo pipefail

# K3s Cluster Bootstrap Setup Wizard
# Interactive configuration for easy deployment

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration file
CONFIG_FILE=".env"
CREDENTIALS_DIR=".cluster/credentials"

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root!"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing=()
    
    # Check required commands
    for cmd in curl git kubectl docker; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing required commands: ${missing[*]}"
        print_info "Please install missing dependencies first."
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running or accessible"
        print_info "Please start Docker and ensure your user has access"
        exit 1
    fi
    
    print_success "All prerequisites met!"
}

# Get user input with default value
get_input() {
    local prompt=$1
    local default=$2
    local secret=${3:-false}
    local value
    
    if [ "$secret" = true ]; then
        read -s -p "$prompt [$default]: " value
        echo
    else
        read -p "$prompt [$default]: " value
    fi
    
    echo "${value:-$default}"
}

# Validate domain
validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid domain format: $domain"
        return 1
    fi
    return 0
}

# Validate email
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid email format: $email"
        return 1
    fi
    return 0
}

# Setup basic configuration
setup_basic_config() {
    print_header "Basic Configuration"
    
    # Domain
    while true; do
        DOMAIN=$(get_input "Enter your domain (e.g., example.com)" "")
        if validate_domain "$DOMAIN"; then
            break
        fi
    done
    
    # Admin email
    while true; do
        ADMIN_EMAIL=$(get_input "Enter admin email" "admin@$DOMAIN")
        if validate_email "$ADMIN_EMAIL"; then
            break
        fi
    done
    
    # Environment
    print_info "Select deployment environment:"
    echo "  1) Local (development)"
    echo "  2) Hetzner Cloud"
    echo "  3) Other cloud/VPS"
    read -p "Choice [1]: " env_choice
    
    case ${env_choice:-1} in
        1)
            ENVIRONMENT="local"
            ;;
        2)
            ENVIRONMENT="hetzner"
            HETZNER_API_TOKEN=$(get_input "Enter Hetzner API token" "" true)
            ;;
        3)
            ENVIRONMENT="vps"
            SERVER_IP=$(get_input "Enter server IP address" "")
            ;;
    esac
}

# Setup GitHub OAuth
setup_github_oauth() {
    print_header "GitHub OAuth Configuration"
    
    print_info "Create a GitHub OAuth App:"
    print_info "1. Go to: https://github.com/settings/applications/new"
    print_info "2. Application name: K3s Cluster ($DOMAIN)"
    print_info "3. Homepage URL: https://$DOMAIN"
    print_info "4. Authorization callback URL: https://$DOMAIN/oauth2/callback"
    print_info ""
    
    read -p "Press Enter when ready to continue..."
    
    GITHUB_CLIENT_ID=$(get_input "Enter GitHub Client ID" "")
    GITHUB_CLIENT_SECRET=$(get_input "Enter GitHub Client Secret" "" true)
    GITHUB_ORG=$(get_input "Enter GitHub Organization (optional)" "")
}

# Setup email configuration
setup_email_config() {
    print_header "Email Configuration (Optional)"
    
    read -p "Configure email notifications? [y/N]: " configure_email
    if [[ "${configure_email,,}" == "y" ]]; then
        SMTP_HOST=$(get_input "SMTP Host" "smtp.gmail.com")
        SMTP_PORT=$(get_input "SMTP Port" "587")
        SMTP_USERNAME=$(get_input "SMTP Username" "$ADMIN_EMAIL")
        SMTP_PASSWORD=$(get_input "SMTP Password" "" true)
        SMTP_USE_TLS=$(get_input "Use TLS" "true")
        SMTP_FROM=$(get_input "From Address" "noreply@$DOMAIN")
    fi
}

# Select components
select_components() {
    print_header "Component Selection"
    
    print_info "Select installation profile:"
    echo "  1) Essential (Core + Auth + Monitoring + Git/CI)"
    echo "  2) Developer (Essential + Registries + Error tracking)"
    echo "  3) Full Stack (Everything)"
    echo "  4) Custom"
    read -p "Choice [2]: " profile_choice
    
    case ${profile_choice:-2} in
        1)
            COMPONENTS="base,storage,secrets,auth,monitoring,gitea,control-panel"
            ;;
        2)
            COMPONENTS="base,storage,secrets,auth,monitoring,registry,npm-registry,gitea,drone,argocd,sentry,control-panel"
            ;;
        3)
            COMPONENTS="all"
            ;;
        4)
            select_custom_components
            ;;
    esac
    
    # Ask about advanced components
    if [[ "$COMPONENTS" != "all" ]]; then
        read -p "Include Longhorn distributed storage? [y/N]: " include_longhorn
        if [[ "${include_longhorn,,}" == "y" ]]; then
            COMPONENTS="$COMPONENTS,longhorn"
        fi
        
        read -p "Include Authentik identity provider? [y/N]: " include_authentik
        if [[ "${include_authentik,,}" == "y" ]]; then
            COMPONENTS="$COMPONENTS,authentik"
        fi
    fi
}

# Custom component selection
select_custom_components() {
    local selected_components="base,storage,secrets,auth"
    
    declare -A components=(
        ["monitoring"]="Prometheus, Grafana, AlertManager"
        ["registry"]="Harbor container registry"
        ["npm-registry"]="Verdaccio NPM registry"
        ["gitea"]="Git repository hosting"
        ["drone"]="CI/CD platform"
        ["argocd"]="GitOps deployment"
        ["k8s-dashboard"]="Kubernetes Dashboard"
        ["vaultwarden"]="Password manager"
        ["minio"]="S3-compatible storage"
        ["nextcloud"]="File sharing platform"
        ["sentry"]="Error tracking"
        ["plausible"]="Web analytics"
        ["matrix"]="Chat server"
        ["mastodon"]="Social network"
        ["mumble"]="Voice chat"
        ["jupyterhub"]="Jupyter notebooks"
        ["longhorn"]="Distributed storage"
        ["authentik"]="Identity provider"
        ["control-panel"]="Web management UI"
        ["backup"]="Backup solution"
    )
    
    print_info "Select components to install:"
    for comp in "${!components[@]}"; do
        read -p "Install $comp (${components[$comp]})? [y/N]: " install_comp
        if [[ "${install_comp,,}" == "y" ]]; then
            selected_components="$selected_components,$comp"
        fi
    done
    
    COMPONENTS="$selected_components"
}

# Generate secure passwords
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Create environment file
create_env_file() {
    print_header "Creating Configuration File"
    
    cat > "$CONFIG_FILE" <<EOF
# K3s Cluster Bootstrap Configuration
# Generated on $(date)

# Domain Configuration
DOMAIN=$DOMAIN
ADMIN_EMAIL=$ADMIN_EMAIL

# GitHub OAuth
GITHUB_CLIENT_ID=$GITHUB_CLIENT_ID
GITHUB_CLIENT_SECRET=$GITHUB_CLIENT_SECRET
GITHUB_ORG=$GITHUB_ORG

# Email Configuration
SMTP_HOST=${SMTP_HOST:-}
SMTP_PORT=${SMTP_PORT:-587}
SMTP_USERNAME=${SMTP_USERNAME:-}
SMTP_PASSWORD=${SMTP_PASSWORD:-}
SMTP_USE_TLS=${SMTP_USE_TLS:-true}
SMTP_FROM=${SMTP_FROM:-noreply@$DOMAIN}

# Deployment Configuration
ENVIRONMENT=$ENVIRONMENT
COMPONENTS=$COMPONENTS
EOF

    if [[ "$ENVIRONMENT" == "hetzner" ]]; then
        echo "HETZNER_API_TOKEN=$HETZNER_API_TOKEN" >> "$CONFIG_FILE"
    elif [[ "$ENVIRONMENT" == "vps" ]]; then
        echo "SERVER_IP=$SERVER_IP" >> "$CONFIG_FILE"
    fi
    
    # Add storage configuration
    if [[ "$COMPONENTS" == *"longhorn"* ]]; then
        echo "DEFAULT_STORAGE_CLASS=longhorn" >> "$CONFIG_FILE"
    else
        echo "DEFAULT_STORAGE_CLASS=local-path" >> "$CONFIG_FILE"
    fi
    
    print_success "Configuration saved to $CONFIG_FILE"
}

# Pre-deployment checklist
pre_deployment_checklist() {
    print_header "Pre-Deployment Checklist"
    
    print_info "Before proceeding, ensure:"
    echo "  ✓ Domain DNS is configured (A record pointing to server IP)"
    echo "  ✓ Firewall allows ports: 80, 443, 6443 (K3s API)"
    if [[ "$COMPONENTS" == *"mumble"* ]]; then
        echo "  ✓ Firewall allows port: 64738 (TCP/UDP for Mumble)"
    fi
    echo "  ✓ Server has at least 4GB RAM and 20GB disk space"
    echo ""
    
    read -p "Continue with deployment? [Y/n]: " continue_deploy
    if [[ "${continue_deploy,,}" == "n" ]]; then
        print_info "Deployment cancelled. Run this script again when ready."
        exit 0
    fi
}

# Deploy cluster
deploy_cluster() {
    print_header "Deploying K3s Cluster"
    
    # Source the environment file
    source "$CONFIG_FILE"
    
    # Run bootstrap
    print_info "Starting deployment..."
    ./bootstrap.sh \
        --environment "$ENVIRONMENT" \
        --components "$COMPONENTS" \
        --domain "$DOMAIN"
    
    print_success "Deployment completed!"
}

# Post-deployment information
post_deployment_info() {
    print_header "Post-Deployment Information"
    
    # Run validation if available
    if [[ -f "${SCRIPT_DIR}/scripts/validate-deployment.sh" ]]; then
        print_info "Running deployment validation..."
        bash "${SCRIPT_DIR}/scripts/validate-deployment.sh"
    else
        print_info "Your K3s cluster is ready!"
        echo ""
        echo "Access your services at:"
        echo "  Control Panel: https://$DOMAIN"
        
        if [[ "$COMPONENTS" == *"gitea"* ]]; then
            echo "  Git Repository: https://git.$DOMAIN"
        fi
        if [[ "$COMPONENTS" == *"monitoring"* ]]; then
            echo "  Monitoring: https://metrics.$DOMAIN"
        fi
        if [[ "$COMPONENTS" == *"registry"* ]]; then
            echo "  Container Registry: https://registry.$DOMAIN"
        fi
        if [[ "$COMPONENTS" == *"argocd"* ]]; then
            echo "  ArgoCD: https://argocd.$DOMAIN"
        fi
    fi
    
    echo ""
    print_info "Credentials are saved in: $CREDENTIALS_DIR/"
    echo ""
    print_warning "IMPORTANT: Save the $CONFIG_FILE and $CREDENTIALS_DIR directory securely!"
    
    # Show control panel setup reminder
    if [[ "$COMPONENTS" == *"control-panel"* ]]; then
        echo ""
        print_info "Control Panel will auto-discover and configure all services."
        print_info "Login with your GitHub account to access the dashboard."
    fi
    
    echo ""
    print_success "🎉 Deployment completed successfully!"
    print_info "Need help? Check QUICKSTART.md or run ./scripts/validate-deployment.sh"
}

# Main setup flow
main() {
    clear
    print_header "K3s Cluster Bootstrap Setup Wizard"
    
    check_root
    check_prerequisites
    
    # Run pre-flight checks if available
    if [[ -f "${SCRIPT_DIR}/scripts/preflight-check.sh" ]]; then
        print_info "Running pre-flight system checks..."
        if ! bash "${SCRIPT_DIR}/scripts/preflight-check.sh"; then
            print_error "Pre-flight checks failed!"
            read -p "Continue anyway? [y/N]: " continue_anyway
            if [[ "${continue_anyway,,}" != "y" ]]; then
                exit 1
            fi
        fi
    fi
    
    # Check if config already exists
    if [[ -f "$CONFIG_FILE" ]]; then
        print_warning "Configuration file already exists!"
        read -p "Overwrite existing configuration? [y/N]: " overwrite
        if [[ "${overwrite,,}" != "y" ]]; then
            print_info "Using existing configuration."
            source "$CONFIG_FILE"
            pre_deployment_checklist
            deploy_cluster
            post_deployment_info
            return
        fi
    fi
    
    # Setup configuration
    setup_basic_config
    setup_github_oauth
    setup_email_config
    select_components
    create_env_file
    pre_deployment_checklist
    deploy_cluster
    post_deployment_info
}

# Run main function
main "$@"