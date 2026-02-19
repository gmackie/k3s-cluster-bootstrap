#!/bin/bash
set -euo pipefail

# Harbor Container Registry installation
# This script is called by bootstrap.sh with environment variables set

# Source common functions if not already loaded
if ! command -v info >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/common.sh"
fi

# Source state management functions
if ! command -v save_credentials >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/.cluster-state.sh"
fi

# Component metadata
COMPONENT_NAME="registry"
COMPONENT_NAMESPACE="registry"

info "Installing Harbor container registry..."

# Check required variables
if [[ -z "${DOMAIN:-}" ]]; then
    error "DOMAIN is required for Harbor installation"
fi

# Create namespace
ensure_namespace "$COMPONENT_NAMESPACE"

# Generate passwords and secrets
HARBOR_ADMIN_PASSWORD=$(generate_password)
HARBOR_DB_PASSWORD=$(generate_password)
HARBOR_REDIS_PASSWORD=$(generate_password)
HARBOR_REGISTRY_PASSWORD=$(generate_password)
CORE_SECRET=$(openssl rand -base64 32)
JOBSERVICE_SECRET=$(openssl rand -base64 32)

# Save credentials
save_credentials "$COMPONENT_NAME" "HARBOR_ADMIN_USER=admin
HARBOR_ADMIN_PASSWORD=$HARBOR_ADMIN_PASSWORD
HARBOR_URL=https://registry.${DOMAIN}
HARBOR_DB_PASSWORD=$HARBOR_DB_PASSWORD"

# Add Harbor Helm repository
info "Adding Harbor Helm repository..."
helm repo add harbor https://helm.goharbor.io || true
helm repo update

# Create Harbor values
cat > /tmp/harbor-values.yaml <<EOF
# External access configuration
expose:
  type: clusterIP
  tls:
    enabled: false  # We'll handle TLS with cert-manager
  clusterIP:
    name: harbor

# External URL
externalURL: https://registry.${DOMAIN}

# Persistence configuration
persistence:
  enabled: true
  persistentVolumeClaim:
    registry:
      storageClass: ${STORAGE_CLASS:-longhorn}
      size: 20Gi
    chartmuseum:
      storageClass: ${STORAGE_CLASS:-longhorn}
      size: 5Gi
    jobservice:
      jobLog:
        storageClass: ${STORAGE_CLASS:-longhorn}
        size: 1Gi
      scanDataExports:
        storageClass: ${STORAGE_CLASS:-longhorn}
        size: 1Gi
    database:
      storageClass: ${STORAGE_CLASS:-longhorn}
      size: 2Gi
    redis:
      storageClass: ${STORAGE_CLASS:-longhorn}
      size: 1Gi
    trivy:
      storageClass: ${STORAGE_CLASS:-longhorn}
      size: 5Gi

# Harbor admin password
harborAdminPassword: "$HARBOR_ADMIN_PASSWORD"

# Database
database:
  type: internal
  internal:
    password: "$HARBOR_DB_PASSWORD"

# Redis
redis:
  type: internal
  internal:
    password: "$HARBOR_REDIS_PASSWORD"

# Core component
core:
  secret: "$CORE_SECRET"
  xsrfKey: "$(openssl rand -base64 32)"

# Jobservice
jobservice:
  secret: "$JOBSERVICE_SECRET"

# Registry
registry:
  secret: "$(openssl rand -base64 32)"
  credentials:
    username: "harbor_registry_user"
    password: "$HARBOR_REGISTRY_PASSWORD"

# Trivy security scanner
trivy:
  enabled: true
  gitHubToken: ""
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 1Gi

# ChartMuseum (Helm chart repository)
chartmuseum:
  enabled: true
  absoluteUrl: false
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Notary (content trust)
notary:
  enabled: false

# Metrics
metrics:
  enabled: true
  serviceMonitor:
    enabled: true

# Resource limits
core:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 1Gi

jobservice:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 1Gi

registry:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 2Gi

portal:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Security settings
internalTLS:
  enabled: false

# Proxy cache
proxy:
  httpProxy: ""
  httpsProxy: ""
  noProxy: "127.0.0.1,localhost,.local,.internal"
  components:
    - core
    - jobservice
    - trivy
EOF

# Install Harbor
info "Installing Harbor via Helm..."
helm upgrade --install harbor harbor/harbor \
  -f /tmp/harbor-values.yaml \
  -n "$COMPONENT_NAMESPACE" \
  --wait \
  --timeout 15m

# Wait for Harbor to be ready
info "Waiting for Harbor components to be ready..."
wait_for_deployment "$COMPONENT_NAMESPACE" "harbor-core"
wait_for_deployment "$COMPONENT_NAMESPACE" "harbor-jobservice"
wait_for_deployment "$COMPONENT_NAMESPACE" "harbor-portal"
wait_for_deployment "$COMPONENT_NAMESPACE" "harbor-registry"

# Create ingress with OAuth2 authentication
info "Creating Harbor ingress with OAuth2 authentication..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: harbor-ingress
  namespace: $COMPONENT_NAMESPACE
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    # OAuth2 annotations for UI only
    nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.auth-system.svc.cluster.local:4180/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://${DOMAIN}/oauth2/start?rd=\$scheme://\$host\$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Access-Token"
    # Skip auth for API and v2 endpoints (for docker client)
    nginx.ingress.kubernetes.io/configuration-snippet: |
      if (\$request_uri ~* "^/api/.*|^/v2/.*|^/chartrepo/.*|^/service/.*") {
        set \$auth_header "";
      }
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - registry.${DOMAIN}
    secretName: harbor-tls
  rules:
  - host: registry.${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: harbor
            port:
              number: 80
EOF

# Create image pull secrets for default namespaces
info "Creating image pull secrets..."
for ns in default kube-system; do
  kubectl create secret docker-registry harbor-regcred \
    --docker-server="registry.${DOMAIN}" \
    --docker-username=admin \
    --docker-password="$HARBOR_ADMIN_PASSWORD" \
    --docker-email="${ADMIN_EMAIL:-admin@${DOMAIN}}" \
    -n $ns \
    --dry-run=client -o yaml | kubectl apply -f -
done

# Configure default service account to use the pull secret
kubectl patch serviceaccount default -n default -p '{"imagePullSecrets": [{"name": "harbor-regcred"}]}'

# Clean up
rm -f /tmp/harbor-values.yaml

success "Harbor registry installed successfully!"
info "=== Harbor Access Information ==="
info "URL: https://registry.${DOMAIN}"
info "Username: admin"
info "Password: Saved in .cluster/credentials/registry.conf"
info ""
info "=== Docker Login ==="
info "docker login registry.${DOMAIN}"
info ""
info "=== Push Image Example ==="
info "docker tag myapp:latest registry.${DOMAIN}/library/myapp:latest"
info "docker push registry.${DOMAIN}/library/myapp:latest"
info ""
info "=== Features Enabled ==="
info "✓ Container registry with web UI"
info "✓ Vulnerability scanning with Trivy"
info "✓ Helm chart repository (ChartMuseum)"
info "✓ Project-based access control"
info "✓ Image replication and retention policies"
info "✓ Webhook notifications"
info ""
info "=== Notes ==="
info "- Web UI requires OAuth2 authentication"
info "- Docker CLI access uses Harbor credentials"
info "- Default 'library' project is public"
info "- Create projects via UI for team isolation"