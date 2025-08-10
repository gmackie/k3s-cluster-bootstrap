#!/bin/bash
set -euo pipefail

# ArgoCD Component Installation
# GitOps continuous deployment for Kubernetes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="argocd"
COMPONENT_NAMESPACE="argocd"
ARGOCD_VERSION="v2.9.3"

install_argocd() {
    info "Installing ArgoCD GitOps platform..."
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for ArgoCD installation"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Install ArgoCD
    info "Deploying ArgoCD ${ARGOCD_VERSION}..."
    kubectl apply -n ${COMPONENT_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    info "Waiting for ArgoCD deployment..."
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n ${COMPONENT_NAMESPACE}
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n ${COMPONENT_NAMESPACE}
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-redis -n ${COMPONENT_NAMESPACE}
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-dex-server -n ${COMPONENT_NAMESPACE}
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n ${COMPONENT_NAMESPACE}
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-notifications-controller -n ${COMPONENT_NAMESPACE}
    
    # Generate admin password if not exists
    if ! kubectl get secret argocd-initial-admin-secret -n ${COMPONENT_NAMESPACE} >/dev/null 2>&1; then
        info "Generating ArgoCD admin password..."
        ADMIN_PASSWORD=$(generate_password)
        kubectl create secret generic argocd-initial-admin-secret \
            --namespace=${COMPONENT_NAMESPACE} \
            --from-literal=password=$(htpasswd -nbBC 10 "" "$ADMIN_PASSWORD" | tr -d ':\n' | sed 's/$2y/$2a/')
    else
        # Retrieve existing password
        ADMIN_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n ${COMPONENT_NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)
    fi
    
    # Patch ArgoCD server for insecure mode (behind ingress)
    info "Configuring ArgoCD server..."
    kubectl patch deployment argocd-server -n ${COMPONENT_NAMESPACE} --type='json' -p='[
        {"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--insecure"}
    ]'
    
    # Configure RBAC for GitHub OAuth
    info "Configuring ArgoCD RBAC..."
    kubectl patch configmap argocd-rbac-cm -n ${COMPONENT_NAMESPACE} --type merge -p '{"data":{"policy.csv":"g, argocd-admins, role:admin\ng, \"'${GITHUB_ORG:-}'\":*, role:readonly","policy.default":"role:readonly"}}'
    
    # Configure ArgoCD URL
    kubectl patch configmap argocd-cm -n ${COMPONENT_NAMESPACE} --type merge -p '{"data":{"url":"https://argocd.'${DOMAIN}'"}}'
    
    # Create ingress
    info "Creating ArgoCD ingress..."
    envsubst < "${SCRIPT_DIR}/argocd-ingress.yaml" | kubectl apply -f -
    
    # Create ArgoCD CLI config
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: ${COMPONENT_NAMESPACE}
data:
  server.insecure: "true"
  server.grpc.insecure: "true"
  server.disable.auth: "false"
  reposerver.parallelism.limit: "0"
EOF
    
    # Configure GitHub OAuth integration
    if [[ -n "${GITHUB_CLIENT_ID:-}" ]] && [[ -n "${GITHUB_CLIENT_SECRET:-}" ]]; then
        info "Configuring GitHub OAuth for ArgoCD..."
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: ${COMPONENT_NAMESPACE}
type: Opaque
stringData:
  dex.github.clientID: "${GITHUB_CLIENT_ID}"
  dex.github.clientSecret: "${GITHUB_CLIENT_SECRET}"
EOF
        
        # Update Dex configuration
        kubectl patch configmap argocd-cm -n ${COMPONENT_NAMESPACE} --type merge -p '{"data":{"dex.config":"connectors:\n- type: github\n  id: github\n  name: GitHub\n  config:\n    clientID: $dex.github.clientID\n    clientSecret: $dex.github.clientSecret\n    orgs:\n    - name: '${GITHUB_ORG:-}''\n"}}'
    fi
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/argocd.conf" <<EOF
ARGOCD_URL=https://argocd.${DOMAIN}
ADMIN_USER=admin
ADMIN_PASSWORD=$ADMIN_PASSWORD

# CLI Access:
# 1. Install ArgoCD CLI: brew install argocd
# 2. Login: argocd login argocd.${DOMAIN} --username admin --password '$ADMIN_PASSWORD' --insecure
# 3. List apps: argocd app list

# API Access:
# Get token: argocd account generate-token
# Use token: curl -H "Authorization: Bearer <token>" https://argocd.${DOMAIN}/api/v1/applications

# Example Application:
# argocd app create my-app \\
#   --repo https://git.${DOMAIN}/myorg/myrepo.git \\
#   --path kubernetes \\
#   --dest-server https://kubernetes.default.svc \\
#   --dest-namespace default
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/argocd.conf"
    
    # Create bootstrap application for this cluster
    info "Creating bootstrap application..."
    cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bootstrap
  namespace: ${COMPONENT_NAMESPACE}
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://git.${DOMAIN}/infrastructure/k3s-cluster-bootstrap.git
    targetRevision: HEAD
    path: components
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
    syncOptions:
    - CreateNamespace=true
EOF
    
    # Create app-of-apps pattern structure
    info "Creating ArgoCD app patterns..."
    cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: infrastructure
  namespace: ${COMPONENT_NAMESPACE}
spec:
  description: Infrastructure components
  sourceRepos:
  - 'https://git.${DOMAIN}/*'
  - 'https://github.com/*'
  destinations:
  - namespace: '*'
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: applications
  namespace: ${COMPONENT_NAMESPACE}
spec:
  description: User applications
  sourceRepos:
  - 'https://git.${DOMAIN}/*'
  destinations:
  - namespace: '*'
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'
EOF
    
    success "ArgoCD installed successfully!"
    
    # Display access information
    info "ArgoCD Access Information:"
    echo "  URL: https://argocd.${DOMAIN}"
    echo "  Admin User: admin"
    echo "  Admin Password: $ADMIN_PASSWORD"
    echo ""
    echo "Features:"
    echo "  ✓ GitOps continuous deployment"
    echo "  ✓ Multi-cluster management"
    echo "  ✓ Automated sync policies"
    echo "  ✓ Rollback capabilities"
    echo "  ✓ RBAC with GitHub teams"
    echo "  ✓ Webhook integration"
    echo "  ✓ ApplicationSets for multi-env"
    echo "  ✓ Notifications support"
    echo ""
    echo "Quick Start:"
    echo "  1. Login to ArgoCD UI"
    echo "  2. Connect your Git repository"
    echo "  3. Create an Application"
    echo "  4. Sync to deploy"
    echo ""
    echo "CLI Example:"
    echo "  argocd login argocd.${DOMAIN} --username admin"
    echo "  argocd repo add https://git.${DOMAIN}/myrepo.git"
    echo "  argocd app create myapp --repo https://git.${DOMAIN}/myrepo.git --path k8s --dest-server https://kubernetes.default.svc"
    echo ""
    echo "Credentials saved to: ${SCRIPT_DIR}/../../.cluster/credentials/argocd.conf"
}

uninstall_argocd() {
    info "Uninstalling ArgoCD..."
    
    # Delete all applications first
    kubectl delete applications.argoproj.io --all -n ${COMPONENT_NAMESPACE} || true
    
    # Delete ArgoCD
    kubectl delete -n ${COMPONENT_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml || true
    
    # Delete namespace
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "ArgoCD uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_argocd
        ;;
    uninstall)
        uninstall_argocd
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac