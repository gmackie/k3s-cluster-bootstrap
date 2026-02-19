#!/bin/bash
set -euo pipefail

export KUBECONFIG=~/.kube/config-hetzner
DOMAIN="gmac.io"
NAMESPACE="registry"
STORAGE_CLASS="longhorn"

echo "Installing Harbor container registry..."

# Add Harbor Helm repository
helm repo add harbor https://helm.goharbor.io || true
helm repo update

# Generate passwords
HARBOR_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
HARBOR_DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Save credentials
mkdir -p .cluster/credentials
cat > .cluster/credentials/harbor.conf <<EOF
HARBOR_ADMIN_USER=admin
HARBOR_ADMIN_PASSWORD=$HARBOR_ADMIN_PASSWORD
HARBOR_URL=https://registry.${DOMAIN}
EOF
chmod 600 .cluster/credentials/harbor.conf

# Create Harbor values
cat > /tmp/harbor-values.yaml <<EOF
expose:
  type: clusterIP
  tls:
    enabled: false

externalURL: https://registry.${DOMAIN}

harborAdminPassword: "$HARBOR_ADMIN_PASSWORD"

persistence:
  enabled: true
  persistentVolumeClaim:
    registry:
      storageClass: ${STORAGE_CLASS}
      size: 20Gi
    chartmuseum:
      storageClass: ${STORAGE_CLASS}
      size: 5Gi
    jobservice:
      jobLog:
        storageClass: ${STORAGE_CLASS}
        size: 1Gi
    database:
      storageClass: ${STORAGE_CLASS}
      size: 2Gi
    redis:
      storageClass: ${STORAGE_CLASS}
      size: 1Gi
    trivy:
      storageClass: ${STORAGE_CLASS}
      size: 5Gi

database:
  type: internal
  internal:
    password: "$HARBOR_DB_PASSWORD"

trivy:
  enabled: true

chartmuseum:
  enabled: true

notary:
  enabled: false

metrics:
  enabled: true
  serviceMonitor:
    enabled: true

# Resource limits for smaller deployment
core:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

jobservice:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

registry:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

portal:
  replicas: 1
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

trivy:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
EOF

# Install Harbor
echo "Installing Harbor via Helm..."
helm upgrade --install harbor harbor/harbor \
  -f /tmp/harbor-values.yaml \
  -n "$NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout 10m

# Create ingress with OAuth2 authentication
echo "Creating Harbor ingress..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: harbor-ingress
  namespace: $NAMESPACE
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    # OAuth2 for UI, skip for API/CLI access
    nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.auth-system.svc.cluster.local:4180/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://${DOMAIN}/oauth2/start?rd=\$scheme://\$host\$escaped_request_uri"
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

# Clean up
rm -f /tmp/harbor-values.yaml

echo "Harbor installed successfully!"
echo "=== Access Information ==="
echo "URL: https://registry.${DOMAIN}"
echo "Username: admin"
echo "Password: $HARBOR_ADMIN_PASSWORD"
echo ""
echo "=== Docker Login ==="
echo "docker login registry.${DOMAIN}"
echo ""
echo "=== NPM Configuration ==="
echo "Create a project in Harbor UI, then configure npm:"
echo "npm config set @yourscope:registry https://registry.${DOMAIN}/chartrepo/PROJECT_NAME/"
echo "npm login --registry https://registry.${DOMAIN}/chartrepo/PROJECT_NAME/ --scope=@yourscope"