#!/bin/bash
set -euo pipefail

# JupyterHub Component Installation
# Provides multi-user Jupyter notebook server

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="jupyterhub"
COMPONENT_NAMESPACE="jupyterhub"

install_jupyterhub() {
    info "Installing JupyterHub..."
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for JupyterHub installation"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate secrets
    JUPYTERHUB_PROXY_TOKEN=$(openssl rand -hex 32)
    JUPYTERHUB_COOKIE_SECRET=$(openssl rand -hex 32)
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/jupyterhub.conf" <<EOF
JUPYTERHUB_URL=https://notebook.${DOMAIN}
JUPYTERHUB_PROXY_TOKEN=$JUPYTERHUB_PROXY_TOKEN
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/jupyterhub.conf"
    
    # Add JupyterHub Helm repository
    helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
    helm repo update
    
    # Create values file
    cat > /tmp/jupyterhub-values.yaml <<EOF
proxy:
  secretToken: "$JUPYTERHUB_PROXY_TOKEN"
  service:
    type: ClusterIP
  https:
    enabled: false  # TLS handled by ingress

hub:
  config:
    GitHubOAuthenticator:
      client_id: "${GITHUB_CLIENT_ID}"
      client_secret: "${GITHUB_CLIENT_SECRET}"
      oauth_callback_url: "https://notebook.${DOMAIN}/hub/oauth_callback"
      allowed_organizations:
        - "${GITHUB_ORG:-}"
    JupyterHub:
      authenticator_class: github
      admin_users:
        - "${GITHUB_USER:-admin}"
    Authenticator:
      auto_login: true
  cookieSecret: "$JUPYTERHUB_COOKIE_SECRET"
  baseUrl: /
  db:
    type: sqlite-pvc
    pvc:
      accessModes:
        - ReadWriteOnce
      storage: 1Gi
      storageClassName: local-path

singleuser:
  image:
    name: jupyter/datascience-notebook
    tag: latest
  profileList:
    - display_name: "Minimal environment"
      description: "Base Python environment"
      default: true
    - display_name: "Data Science"
      description: "Includes pandas, matplotlib, scipy"
      kubespawner_override:
        image: jupyter/datascience-notebook:latest
    - display_name: "TensorFlow"
      description: "TensorFlow GPU environment"
      kubespawner_override:
        image: jupyter/tensorflow-notebook:latest
    - display_name: "R"
      description: "R programming environment"
      kubespawner_override:
        image: jupyter/r-notebook:latest
  storage:
    type: dynamic
    dynamic:
      storageClass: local-path
      pvcNameTemplate: claim-{username}{servername}
      volumeNameTemplate: volume-{username}{servername}
      storageAccessModes: [ReadWriteOnce]
    capacity: 10Gi
  cpu:
    limit: 2
    guarantee: 0.5
  memory:
    limit: 4G
    guarantee: 1G

scheduling:
  userScheduler:
    enabled: false
  corePods:
    nodeAffinity:
      matchNodePurpose: prefer

prePuller:
  hook:
    enabled: false
  continuous:
    enabled: true

ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    # OAuth2 proxy integration
    nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.auth-system.svc.cluster.local:4180/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://${DOMAIN}/oauth2/start?rd=\$scheme://\$host\$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email"
    # Skip auth for OAuth callback
    nginx.ingress.kubernetes.io/configuration-snippet: |
      location /hub/oauth_callback {
        proxy_pass http://upstream_balancer;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
      }
  hosts:
    - notebook.${DOMAIN}
  tls:
    - secretName: jupyterhub-tls
      hosts:
        - notebook.${DOMAIN}

cull:
  enabled: true
  timeout: 3600
  every: 600
  maxAge: 0
EOF
    
    # Install JupyterHub
    info "Installing JupyterHub via Helm..."
    helm upgrade --install jupyterhub jupyterhub/jupyterhub \
      --version 3.0.0 \
      -f /tmp/jupyterhub-values.yaml \
      -n ${COMPONENT_NAMESPACE} \
      --wait \
      --timeout 10m
    
    # Clean up
    rm -f /tmp/jupyterhub-values.yaml
    
    success "JupyterHub installed successfully!"
    
    # Display access information
    info "JupyterHub Access Information:"
    echo "  URL: https://notebook.${DOMAIN}"
    echo "  Authentication: GitHub OAuth (${GITHUB_ORG:-any user})"
    echo ""
    echo "Available notebook environments:"
    echo "  - Minimal Python"
    echo "  - Data Science (pandas, matplotlib, scipy)"
    echo "  - TensorFlow"
    echo "  - R"
    echo ""
    echo "Users get 10GB persistent storage"
}

uninstall_jupyterhub() {
    info "Uninstalling JupyterHub..."
    
    helm uninstall jupyterhub -n ${COMPONENT_NAMESPACE} || true
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "JupyterHub uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_jupyterhub
        ;;
    uninstall)
        uninstall_jupyterhub
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac