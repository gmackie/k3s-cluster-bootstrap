#!/bin/bash
set -euo pipefail

# Deployment Validation Script
# Verifies all components are properly deployed and accessible

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load environment
if [[ -f .env ]]; then
    source .env
fi

DOMAIN="${DOMAIN:-localhost}"
CHECKS_PASSED=0
CHECKS_FAILED=0

print_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

check_service() {
    local name=$1
    local namespace=$2
    local url=${3:-}
    
    echo -ne "${BLUE}[CHECK]${NC} $name... "
    
    # Check if namespace exists
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        echo -e "${YELLOW}SKIP${NC} (not deployed)"
        return
    fi
    
    # Check if pods are running
    local ready_pods=$(kubectl get pods -n "$namespace" -o json | jq -r '.items[] | select(.status.phase == "Running") | .metadata.name' | wc -l)
    
    if [[ $ready_pods -gt 0 ]]; then
        echo -ne "${GREEN}RUNNING${NC} "
        
        # Check URL if provided
        if [[ -n "$url" ]]; then
            if curl -sSf -o /dev/null --connect-timeout 5 "$url" 2>/dev/null; then
                echo -e "(${GREEN}URL OK${NC})"
                ((CHECKS_PASSED++))
            else
                echo -e "(${YELLOW}URL unreachable${NC})"
                ((CHECKS_PASSED++))
            fi
        else
            echo
            ((CHECKS_PASSED++))
        fi
    else
        echo -e "${RED}FAIL${NC} (no running pods)"
        ((CHECKS_FAILED++))
    fi
}

check_ingress() {
    local name=$1
    local host=$2
    
    echo -ne "${BLUE}[CHECK]${NC} Ingress $name... "
    
    if kubectl get ingress -A | grep -q "$host"; then
        echo -e "${GREEN}CONFIGURED${NC}"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}NOT FOUND${NC}"
        ((CHECKS_FAILED++))
    fi
}

check_storage() {
    echo -ne "${BLUE}[CHECK]${NC} Storage classes... "
    
    local storage_classes=$(kubectl get storageclass -o name | wc -l)
    if [[ $storage_classes -gt 0 ]]; then
        echo -e "${GREEN}AVAILABLE${NC} ($storage_classes classes)"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}NONE${NC}"
        ((CHECKS_FAILED++))
    fi
}

check_certificates() {
    echo -ne "${BLUE}[CHECK]${NC} TLS Certificates... "
    
    local certs=$(kubectl get certificate -A 2>/dev/null | grep -c True || echo 0)
    if [[ $certs -gt 0 ]]; then
        echo -e "${GREEN}READY${NC} ($certs certificates)"
        ((CHECKS_PASSED++))
    else
        echo -e "${YELLOW}PENDING${NC}"
    fi
}

print_service_urls() {
    print_header "Service URLs"
    
    echo "Your services are available at:"
    echo
    
    if kubectl get namespace control-panel &>/dev/null; then
        echo "  🏠 Control Panel: https://$DOMAIN"
    fi
    
    if kubectl get namespace gitea &>/dev/null; then
        echo "  📦 Git Repository: https://git.$DOMAIN"
    fi
    
    if kubectl get namespace drone &>/dev/null; then
        echo "  🚀 CI/CD Platform: https://ci.$DOMAIN"
    fi
    
    if kubectl get namespace harbor &>/dev/null; then
        echo "  🐳 Container Registry: https://registry.$DOMAIN"
    fi
    
    if kubectl get namespace verdaccio &>/dev/null; then
        echo "  📦 NPM Registry: https://npm.$DOMAIN"
    fi
    
    if kubectl get namespace monitoring &>/dev/null; then
        echo "  📊 Monitoring: https://metrics.$DOMAIN"
        echo "  🔔 Alerts: https://alerts.$DOMAIN"
    fi
    
    if kubectl get namespace argocd &>/dev/null; then
        echo "  🔄 GitOps: https://argocd.$DOMAIN"
    fi
    
    if kubectl get namespace kubernetes-dashboard &>/dev/null; then
        echo "  🎛️ K8s Dashboard: https://dashboard.$DOMAIN"
    fi
    
    if kubectl get namespace vaultwarden &>/dev/null; then
        echo "  🔐 Password Manager: https://vault.$DOMAIN"
    fi
    
    if kubectl get namespace minio &>/dev/null; then
        echo "  💾 Object Storage: https://s3-console.$DOMAIN"
    fi
    
    if kubectl get namespace nextcloud &>/dev/null; then
        echo "  📁 File Sharing: https://files.$DOMAIN"
    fi
    
    if kubectl get namespace sentry &>/dev/null; then
        echo "  🐛 Error Tracking: https://sentry.$DOMAIN"
    fi
    
    if kubectl get namespace plausible &>/dev/null; then
        echo "  📈 Analytics: https://analytics.$DOMAIN"
    fi
    
    if kubectl get namespace jupyterhub &>/dev/null; then
        echo "  📓 Notebooks: https://notebook.$DOMAIN"
    fi
    
    if kubectl get namespace matrix &>/dev/null; then
        echo "  💬 Chat: https://chat.$DOMAIN"
    fi
    
    if kubectl get namespace mastodon &>/dev/null; then
        echo "  🐘 Social: https://social.$DOMAIN"
    fi
    
    if kubectl get namespace mumble &>/dev/null; then
        echo "  🎤 Voice: https://voice.$DOMAIN"
    fi
}

# Main validation
main() {
    print_header "K3s Cluster Deployment Validation"
    
    # Check cluster basics
    print_header "Cluster Status"
    
    echo -ne "${BLUE}[CHECK]${NC} Kubernetes API... "
    if kubectl cluster-info &>/dev/null; then
        echo -e "${GREEN}ACCESSIBLE${NC}"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}UNREACHABLE${NC}"
        ((CHECKS_FAILED++))
        exit 1
    fi
    
    echo -ne "${BLUE}[CHECK]${NC} Nodes... "
    local ready_nodes=$(kubectl get nodes | grep -c Ready || echo 0)
    if [[ $ready_nodes -gt 0 ]]; then
        echo -e "${GREEN}READY${NC} ($ready_nodes nodes)"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}NO READY NODES${NC}"
        ((CHECKS_FAILED++))
    fi
    
    check_storage
    check_certificates
    
    # Check core components
    print_header "Core Components"
    check_service "Ingress Controller" "ingress-nginx"
    check_service "Cert Manager" "cert-manager"
    check_service "Sealed Secrets" "sealed-secrets"
    
    # Check deployed services
    print_header "Deployed Services"
    check_service "Control Panel" "control-panel" "https://$DOMAIN"
    check_service "Auth System" "auth-system"
    check_service "Gitea" "gitea" "https://git.$DOMAIN"
    check_service "Drone CI" "drone" "https://ci.$DOMAIN"
    check_service "Harbor Registry" "harbor" "https://registry.$DOMAIN"
    check_service "NPM Registry" "verdaccio" "https://npm.$DOMAIN"
    check_service "Prometheus" "monitoring"
    check_service "Grafana" "monitoring" "https://metrics.$DOMAIN"
    check_service "ArgoCD" "argocd" "https://argocd.$DOMAIN"
    check_service "K8s Dashboard" "kubernetes-dashboard" "https://dashboard.$DOMAIN"
    check_service "Vaultwarden" "vaultwarden" "https://vault.$DOMAIN"
    check_service "MinIO" "minio" "https://s3-console.$DOMAIN"
    check_service "Nextcloud" "nextcloud" "https://files.$DOMAIN"
    check_service "Sentry" "sentry" "https://sentry.$DOMAIN"
    check_service "Plausible" "plausible" "https://analytics.$DOMAIN"
    check_service "JupyterHub" "jupyterhub" "https://notebook.$DOMAIN"
    check_service "Matrix" "matrix" "https://chat.$DOMAIN"
    check_service "Mastodon" "mastodon" "https://social.$DOMAIN"
    check_service "Mumble" "mumble"
    check_service "Longhorn" "longhorn-system"
    check_service "Authentik" "authentik" "https://auth.$DOMAIN"
    
    # Show service URLs
    print_service_urls
    
    # Summary
    print_header "Validation Summary"
    echo -e "Checks passed: ${GREEN}$CHECKS_PASSED${NC}"
    echo -e "Checks failed: ${RED}$CHECKS_FAILED${NC}"
    echo
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ All validation checks passed!${NC}"
        echo "Your K3s cluster is fully operational."
    else
        echo -e "${YELLOW}⚠️  Some checks failed${NC}"
        echo "Review the failed services above."
    fi
    
    # Check credentials
    if [[ -d ".cluster/credentials" ]]; then
        echo
        echo -e "${BLUE}📁 Credentials location:${NC} .cluster/credentials/"
    fi
}

# Run main function
main "$@"