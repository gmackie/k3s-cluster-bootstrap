#!/bin/bash
# Configure registry access for namespaces

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

ACTION="${1:-help}"
NAMESPACE="${2:-default}"

show_usage() {
    cat << EOF
Usage: $0 [action] [namespace]

Configure registry access for Kubernetes namespaces

Actions:
    setup       Setup registry access for a namespace
    test        Test registry access
    list        List configured namespaces
    sync        Sync registry credentials to all namespaces

Examples:
    # Setup registry for default namespace
    $0 setup default

    # Setup for a new namespace
    $0 setup my-app

    # Test registry access
    $0 test

    # Sync credentials to all namespaces
    $0 sync
EOF
}

# Load registry credentials
load_registry_creds() {
    if [[ ! -f "${SCRIPT_DIR}/../.cluster/credentials/registry.conf" ]]; then
        error "Registry not installed. Run registry component first."
    fi
    
    source "${SCRIPT_DIR}/../.cluster/credentials/registry.conf"
}

# Setup registry access for namespace
setup_namespace() {
    local ns="$NAMESPACE"
    
    load_registry_creds
    
    info "Setting up registry access for namespace: $ns"
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$ns" 2>/dev/null || true
    
    # Create docker registry secret
    kubectl create secret docker-registry regcred \
        --docker-server="${HARBOR_URL}" \
        --docker-username="${HARBOR_ADMIN_USER}" \
        --docker-password="${HARBOR_ADMIN_PASSWORD}" \
        --docker-email="${HARBOR_ADMIN_USER}@${DOMAIN:-local}" \
        -n "$ns" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Patch default service account
    kubectl patch serviceaccount default -n "$ns" \
        -p '{"imagePullSecrets": [{"name": "regcred"}]}' || true
    
    # Create sealed secret for GitOps
    if command_exists kubeseal && [[ -f "${SCRIPT_DIR}/../.cluster/sealed-secrets-pub.pem" ]]; then
        info "Creating sealed secret for GitOps..."
        
        kubectl create secret docker-registry regcred \
            --docker-server="${HARBOR_URL}" \
            --docker-username="${HARBOR_ADMIN_USER}" \
            --docker-password="${HARBOR_ADMIN_PASSWORD}" \
            --docker-email="${HARBOR_ADMIN_USER}@${DOMAIN:-local}" \
            -n "$ns" \
            --dry-run=client -o yaml | \
        kubeseal --cert "${SCRIPT_DIR}/../.cluster/sealed-secrets-pub.pem" \
            -o yaml > "${SCRIPT_DIR}/../.cluster/sealed-regcred-${ns}.yaml"
        
        info "Sealed secret saved to: .cluster/sealed-regcred-${ns}.yaml"
    fi
    
    success "Registry access configured for namespace: $ns"
}

# Test registry access
test_registry() {
    load_registry_creds
    
    info "Testing registry access..."
    
    # Test docker login
    echo "$HARBOR_ADMIN_PASSWORD" | docker login "$HARBOR_URL" -u "$HARBOR_ADMIN_USER" --password-stdin
    
    if [[ $? -eq 0 ]]; then
        success "Docker login successful"
        
        # Test push/pull
        info "Testing image push/pull..."
        
        # Pull a small test image
        docker pull alpine:latest
        
        # Tag for our registry
        docker tag alpine:latest "$HARBOR_URL/public/alpine:test"
        
        # Push to registry
        if docker push "$HARBOR_URL/public/alpine:test"; then
            success "Image push successful"
            
            # Test pull from registry
            docker rmi "$HARBOR_URL/public/alpine:test" || true
            if docker pull "$HARBOR_URL/public/alpine:test"; then
                success "Image pull successful"
            else
                error "Image pull failed"
            fi
        else
            error "Image push failed"
        fi
        
        # Cleanup
        docker rmi "$HARBOR_URL/public/alpine:test" alpine:latest || true
    else
        error "Docker login failed"
    fi
}

# List configured namespaces
list_namespaces() {
    info "Namespaces with registry access:"
    
    kubectl get secrets --all-namespaces -o json | \
        jq -r '.items[] | select(.metadata.name=="regcred") | .metadata.namespace' | \
        sort | uniq
}

# Sync credentials to all namespaces
sync_credentials() {
    load_registry_creds
    
    info "Syncing registry credentials to all namespaces..."
    
    # Get all namespaces
    namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
    
    for ns in $namespaces; do
        # Skip system namespaces
        if [[ "$ns" == "kube-system" || "$ns" == "kube-public" || "$ns" == "kube-node-lease" ]]; then
            continue
        fi
        
        info "Updating namespace: $ns"
        setup_namespace "$ns"
    done
    
    success "Registry credentials synced to all namespaces"
}

# Main execution
case $ACTION in
    setup)
        setup_namespace
        ;;
    test)
        test_registry
        ;;
    list)
        list_namespaces
        ;;
    sync)
        sync_credentials
        ;;
    help|*)
        show_usage
        ;;
esac