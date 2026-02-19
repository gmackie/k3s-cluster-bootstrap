#!/bin/bash
set -euo pipefail

# Standalone Gitea installation script
export KUBECONFIG=~/.kube/config-hetzner
DOMAIN="gmac.io"

echo "Installing Gitea Git repository..."

# Create namespace
kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f -

# Add Gitea Helm repository
helm repo add gitea-charts https://dl.gitea.io/charts/
helm repo update

# Generate passwords
GITEA_ADMIN_PASSWORD=$(openssl rand -base64 16)
GITEA_DB_PASSWORD=$(openssl rand -base64 16)

# Save credentials
mkdir -p /tmp/credentials
cat > /tmp/credentials/gitea.conf <<EOF
GITEA_ADMIN_USER=gitea_admin
GITEA_ADMIN_PASSWORD=$GITEA_ADMIN_PASSWORD
GITEA_DB_PASSWORD=$GITEA_DB_PASSWORD
GITEA_URL=https://git.${DOMAIN}
EOF
chmod 600 /tmp/credentials/gitea.conf

# Create Gitea values
cat > /tmp/gitea-values.yaml <<EOF
replicaCount: 1

image:
  repository: gitea/gitea
  tag: 1.21-rootless
  pullPolicy: IfNotPresent

service:
  http:
    type: ClusterIP
    port: 3000
  ssh:
    type: LoadBalancer
    port: 2222

ingress:
  enabled: false

persistence:
  enabled: true
  size: 10Gi
  storageClass: longhorn

gitea:
  admin:
    username: gitea_admin
    password: "$GITEA_ADMIN_PASSWORD"
    email: "admin@${DOMAIN}"
    
  config:
    APP_NAME: "Gitea: Git Service"
    server:
      DOMAIN: git.${DOMAIN}
      ROOT_URL: https://git.${DOMAIN}
      SSH_DOMAIN: git.${DOMAIN}
      SSH_PORT: 2222
      SSH_LISTEN_PORT: 2222
      START_SSH_SERVER: true
      LFS_START_SERVER: true
    service:
      DISABLE_REGISTRATION: false
      REQUIRE_SIGNIN_VIEW: false
      DEFAULT_KEEP_EMAIL_PRIVATE: true
      DEFAULT_ALLOW_CREATE_ORGANIZATION: true
      DEFAULT_ENABLE_TIMETRACKING: true
    actions:
      ENABLED: true
    webhook:
      ALLOWED_HOST_LIST: "*"
    oauth2:
      ENABLE: true
    picture:
      DISABLE_GRAVATAR: false
      ENABLE_FEDERATED_AVATAR: false

postgresql:
  enabled: true
  auth:
    postgresPassword: "$GITEA_DB_PASSWORD"
    database: gitea
  primary:
    persistence:
      enabled: true
      size: 5Gi
      storageClass: longhorn
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi

redis-cluster:
  enabled: false

redis:
  enabled: true
  master:
    persistence:
      enabled: true
      size: 1Gi
      storageClass: longhorn

memcached:
  enabled: false

metrics:
  enabled: true
  serviceMonitor:
    enabled: true
EOF

# Install Gitea using Helm
echo "Installing Gitea via Helm..."
helm upgrade --install gitea gitea-charts/gitea \
  -f /tmp/gitea-values.yaml \
  -n gitea \
  --wait \
  --timeout 10m

# Create ingress with OAuth2 authentication
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitea-ingress
  namespace: gitea
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    # OAuth2 annotations
    nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.auth-system.svc.cluster.local:4180/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://gmac.io/oauth2/start?rd=\$scheme://\$host\$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Access-Token"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - git.${DOMAIN}
    secretName: gitea-tls
  rules:
  - host: git.${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: gitea-http
            port:
              number: 3000
EOF

# Clean up
rm -f /tmp/gitea-values.yaml

echo "Gitea installed successfully!"
echo "=== Gitea Access Information ==="
echo "URL: https://git.${DOMAIN}"
echo "Username: gitea_admin"
echo "Password: $(grep GITEA_ADMIN_PASSWORD /tmp/credentials/gitea.conf | cut -d= -f2)"
echo ""
echo "SSH URL: ssh://git@git.${DOMAIN}:2222/<user>/<repo>.git"
echo ""
echo "Credentials saved to: /tmp/credentials/gitea.conf"