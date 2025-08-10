#!/bin/bash
set -euo pipefail

# Pre-flight Checks for K3s Cluster Bootstrap
# Validates system requirements and prerequisites

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check results
CHECKS_PASSED=0
CHECKS_FAILED=0
WARNINGS=0

# Print functions
print_check() {
    echo -ne "${BLUE}[CHECK]${NC} $1... "
}

print_pass() {
    echo -e "${GREEN}PASS${NC}"
    ((CHECKS_PASSED++))
}

print_fail() {
    echo -e "${RED}FAIL${NC}"
    echo -e "  ${RED}→${NC} $1"
    ((CHECKS_FAILED++))
}

print_warn() {
    echo -e "${YELLOW}WARN${NC}"
    echo -e "  ${YELLOW}→${NC} $1"
    ((WARNINGS++))
}

print_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

# System checks
check_os() {
    print_check "Operating System"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        print_pass
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        print_warn "macOS detected. Linux recommended for production"
    else
        print_fail "Unsupported OS: $OSTYPE"
    fi
}

check_cpu() {
    print_check "CPU Cores (minimum 2)"
    local cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
    if [[ $cores -ge 2 ]]; then
        print_pass
    else
        print_fail "Only $cores CPU core(s) detected. Minimum 2 required"
    fi
}

check_memory() {
    print_check "Memory (minimum 4GB)"
    local mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    local mem_gb=$((mem_kb / 1024 / 1024))
    
    if [[ $mem_gb -ge 4 ]]; then
        print_pass
    elif [[ $mem_gb -ge 2 ]]; then
        print_warn "Only ${mem_gb}GB RAM detected. 4GB recommended"
    else
        print_fail "Only ${mem_gb}GB RAM detected. Minimum 4GB required"
    fi
}

check_disk() {
    print_check "Disk Space (minimum 20GB free)"
    local free_gb=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    
    if [[ $free_gb -ge 20 ]]; then
        print_pass
    elif [[ $free_gb -ge 10 ]]; then
        print_warn "Only ${free_gb}GB free disk space. 20GB recommended"
    else
        print_fail "Only ${free_gb}GB free disk space. Minimum 20GB required"
    fi
}

# Network checks
check_internet() {
    print_check "Internet connectivity"
    if curl -s --head --connect-timeout 5 https://github.com > /dev/null; then
        print_pass
    else
        print_fail "Cannot reach github.com"
    fi
}

check_dns() {
    print_check "DNS resolution"
    if host github.com > /dev/null 2>&1; then
        print_pass
    else
        print_fail "DNS resolution not working"
    fi
}

check_ports() {
    print_check "Required ports availability"
    local ports=(80 443 6443)
    local blocked=()
    
    for port in "${ports[@]}"; do
        if lsof -i :$port > /dev/null 2>&1 || netstat -tuln 2>/dev/null | grep -q ":$port "; then
            blocked+=($port)
        fi
    done
    
    if [[ ${#blocked[@]} -eq 0 ]]; then
        print_pass
    else
        print_fail "Ports already in use: ${blocked[*]}"
    fi
}

# Software checks
check_docker() {
    print_check "Docker"
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            print_pass
        else
            print_fail "Docker daemon not running or not accessible"
        fi
    else
        print_fail "Docker not installed"
    fi
}

check_kubectl() {
    print_check "kubectl"
    if command -v kubectl &> /dev/null; then
        print_pass
    else
        print_fail "kubectl not installed"
    fi
}

check_git() {
    print_check "Git"
    if command -v git &> /dev/null; then
        print_pass
    else
        print_fail "Git not installed"
    fi
}

check_curl() {
    print_check "curl"
    if command -v curl &> /dev/null; then
        print_pass
    else
        print_fail "curl not installed"
    fi
}

check_openssl() {
    print_check "OpenSSL"
    if command -v openssl &> /dev/null; then
        print_pass
    else
        print_warn "OpenSSL not installed. Required for password generation"
    fi
}

# K3s specific checks
check_k3s() {
    print_check "K3s"
    if command -v k3s &> /dev/null; then
        print_warn "K3s already installed. Will use existing installation"
    else
        print_pass
    fi
}

check_systemd() {
    print_check "systemd (for K3s service)"
    if command -v systemctl &> /dev/null; then
        print_pass
    else
        print_warn "systemd not available. K3s service management may be limited"
    fi
}

# Configuration checks
check_env_file() {
    print_check "Environment configuration (.env)"
    if [[ -f .env ]]; then
        print_pass
        source .env
    else
        print_warn "No .env file found. Run setup-wizard.sh to create one"
    fi
}

check_domain() {
    print_check "Domain configuration"
    if [[ -n "${DOMAIN:-}" ]]; then
        print_pass
        
        # Check if domain resolves
        print_check "Domain DNS resolution ($DOMAIN)"
        if host "$DOMAIN" > /dev/null 2>&1; then
            print_pass
        else
            print_warn "Domain does not resolve yet. Configure DNS before deployment"
        fi
    else
        print_warn "No domain configured. Some features will be limited"
    fi
}

check_github_oauth() {
    print_check "GitHub OAuth configuration"
    if [[ -n "${GITHUB_CLIENT_ID:-}" ]] && [[ -n "${GITHUB_CLIENT_SECRET:-}" ]]; then
        print_pass
    else
        print_fail "GitHub OAuth not configured. Required for authentication"
    fi
}

# Firewall checks
check_firewall() {
    print_check "Firewall configuration"
    
    # Check if common firewall tools exist
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            print_warn "UFW firewall is active. Ensure required ports are open"
        else
            print_pass
        fi
    elif command -v firewall-cmd &> /dev/null; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            print_warn "firewalld is active. Ensure required ports are open"
        else
            print_pass
        fi
    else
        print_pass
    fi
}

# SELinux check
check_selinux() {
    print_check "SELinux"
    if command -v getenforce &> /dev/null; then
        local status=$(getenforce)
        if [[ "$status" == "Enforcing" ]]; then
            print_warn "SELinux is enforcing. May require additional configuration"
        else
            print_pass
        fi
    else
        print_pass
    fi
}

# Main execution
main() {
    clear
    print_header "K3s Cluster Bootstrap Pre-flight Checks"
    
    print_header "System Requirements"
    check_os
    check_cpu
    check_memory
    check_disk
    
    print_header "Network Requirements"
    check_internet
    check_dns
    check_ports
    check_firewall
    
    print_header "Software Requirements"
    check_docker
    check_kubectl
    check_git
    check_curl
    check_openssl
    check_systemd
    
    print_header "K3s Environment"
    check_k3s
    check_selinux
    
    print_header "Configuration"
    check_env_file
    check_domain
    check_github_oauth
    
    # Summary
    print_header "Pre-flight Check Summary"
    echo -e "Checks passed: ${GREEN}$CHECKS_PASSED${NC}"
    echo -e "Warnings:      ${YELLOW}$WARNINGS${NC}"
    echo -e "Checks failed: ${RED}$CHECKS_FAILED${NC}"
    echo
    
    if [[ $CHECKS_FAILED -gt 0 ]]; then
        echo -e "${RED}✗ Pre-flight checks failed!${NC}"
        echo "Please resolve the issues above before proceeding."
        exit 1
    elif [[ $WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Pre-flight checks passed with warnings${NC}"
        echo "Review the warnings above. You may proceed, but some features might be limited."
        exit 0
    else
        echo -e "${GREEN}✓ All pre-flight checks passed!${NC}"
        echo "Your system is ready for K3s cluster deployment."
        exit 0
    fi
}

# Run main function
main "$@"