#!/bin/bash
# Test script for bootstrap-v2.sh

# Set required environment variables
export KUBECONFIG=~/.kube/config-hetzner
export GITHUB_CLIENT_ID="Ov23liUoDijhtGOCmugS"
export GITHUB_CLIENT_SECRET="9c65ac30ac6d9fb08cffe5334469c7236b99166d"
export DOMAIN="gmac.io"

# Source the state management functions
source ./.cluster-state.sh

# Initialize state directory if needed
init_state

# Mark already installed components as completed
save_component_state "base" "completed"
save_component_state "storage" "completed" 
save_component_state "longhorn" "completed"
save_component_state "auth" "completed"
save_component_state "monitoring" "completed"
save_component_state "argocd" "completed"
save_component_state "k8s-dashboard" "completed"
save_component_state "control-panel" "completed"

# Save environment config
save_environment_config

echo "=== Current State ==="
echo "Installed components:"
list_installed_components
echo ""

echo "=== Testing Bootstrap v2 ==="
echo "Will install: gitea, registry"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Run bootstrap for remaining components
./bootstrap-v2.sh --environment hetzner --components gitea,registry --domain gmac.io --skip-confirm