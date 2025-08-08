#!/bin/bash
# Common functions and utilities

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

# Show help message
show_help() {
    cat << EOF
K3s Cluster Bootstrap System

Usage: ./bootstrap.sh [OPTIONS]

Options:
    --environment <local|hetzner>   Deployment environment (default: local)
    --components <list>             Comma-separated list of components or 'all'
                                   Available: base,storage,secrets,auth,monitoring,registry,
                                            npm-registry,gitea,k8s-dashboard,matrix,mastodon,
                                            mumble,jupyterhub,control-panel,backup
    --domain <domain>              Domain name for the cluster (optional)
    --node-type <master|agent>     Node type for multi-node setup (default: master)
    --help                         Show this help message

Environment Variables:
    HETZNER_API_TOKEN             Required for Hetzner deployments

Examples:
    # Local single-node cluster with monitoring
    ./bootstrap.sh --environment local --components base,monitoring

    # Hetzner cluster with all components
    export HETZNER_API_TOKEN=your-token
    ./bootstrap.sh --environment hetzner --components all --domain ci.gmac.io

    # Add a worker node to existing cluster
    ./bootstrap.sh --environment local --node-type agent
EOF
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Wait for deployment to be ready
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}
    
    info "Waiting for deployment $deployment in namespace $namespace..."
    kubectl wait --for=condition=available --timeout=${timeout}s \
        deployment/$deployment -n $namespace
}

# Apply kubectl manifest with retry
apply_manifest() {
    local manifest=$1
    local retries=3
    local delay=5
    
    for i in $(seq 1 $retries); do
        if kubectl apply -f "$manifest"; then
            return 0
        fi
        
        if [ $i -lt $retries ]; then
            warn "Failed to apply manifest, retrying in ${delay}s..."
            sleep $delay
        fi
    done
    
    error "Failed to apply manifest after $retries attempts"
}

# Create namespace if it doesn't exist
ensure_namespace() {
    local namespace=$1
    
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        info "Creating namespace: $namespace"
        kubectl create namespace "$namespace"
    fi
}

# Generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Check system requirements
check_requirements() {
    local min_memory=2048  # 2GB in MB
    local min_cpu=2
    
    # Check memory
    local total_memory=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_memory" -lt "$min_memory" ]; then
        warn "System has ${total_memory}MB memory, recommended minimum is ${min_memory}MB"
    fi
    
    # Check CPU
    local cpu_count=$(nproc)
    if [ "$cpu_count" -lt "$min_cpu" ]; then
        warn "System has ${cpu_count} CPU cores, recommended minimum is ${min_cpu}"
    fi
}

# Export functions
export -f info success warn error command_exists wait_for_deployment apply_manifest ensure_namespace generate_password check_requirements