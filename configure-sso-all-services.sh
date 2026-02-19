#!/bin/bash
set -euo pipefail

echo "=== Configuring SSO for All Services ==="

# Ensure we're using the correct kubeconfig
export KUBECONFIG=~/.kube/config-hetzner

# OAuth2 proxy annotations
add_oauth2_annotations() {
    local namespace=$1
    local ingress=$2
    local service=$3
    
    echo "Adding OAuth2 proxy annotations to $namespace/$ingress"
    
    kubectl annotate ingress -n "$namespace" "$ingress" \
        "nginx.ingress.kubernetes.io/auth-url=http://oauth2-proxy.auth-system.svc.cluster.local:4180/oauth2/auth" \
        "nginx.ingress.kubernetes.io/auth-signin=https://gmac.io/oauth2/start?rd=\$scheme://\$host\$escaped_request_uri" \
        "nginx.ingress.kubernetes.io/auth-response-headers=X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Access-Token" \
        --overwrite || true
}

# Services that need SSO added
echo "Adding SSO to Harbor"
add_oauth2_annotations "registry" "harbor-ingress" "Harbor"

# Verdaccio uses its own authentication for npm CLI compatibility
echo "Skipping SSO for Verdaccio (uses htpasswd auth)"

echo "=== SSO configuration complete! ==="

echo "Current SSO-enabled services:"
kubectl get ingress -A -o json | jq -r '.items[] | select(.metadata.annotations."nginx.ingress.kubernetes.io/auth-url") | "- \(.metadata.namespace)/\(.metadata.name) (\(.spec.rules[0].host))"'

echo ""
echo "Note: Some services may have special authentication requirements:"
echo "- Harbor: Uses its own auth system, SSO will protect web UI only"
echo "- Verdaccio: Uses htpasswd authentication (no SSO) for npm CLI compatibility"
echo "- ArgoCD: Has its own OIDC configuration options for deeper integration"
echo "- Grafana: Can be configured with GitHub OAuth directly for better integration"