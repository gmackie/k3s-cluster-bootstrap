#!/bin/bash
set -euo pipefail

export KUBECONFIG=~/.kube/config-hetzner
DOMAIN="gmac.io"
NAMESPACE="registry"
STORAGE_CLASS="longhorn"

echo "Installing minimal Harbor setup..."

# Generate passwords
HARBOR_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Save credentials
mkdir -p .cluster/credentials
cat > .cluster/credentials/harbor.conf <<EOF
HARBOR_ADMIN_USER=admin
HARBOR_ADMIN_PASSWORD=$HARBOR_ADMIN_PASSWORD
HARBOR_URL=https://registry.${DOMAIN}
EOF
chmod 600 .cluster/credentials/harbor.conf

# Create minimal Harbor values
cat > /tmp/harbor-minimal-values.yaml <<EOF
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
      size: 10Gi
    database:
      storageClass: ${STORAGE_CLASS}
      size: 1Gi
    redis:
      storageClass: ${STORAGE_CLASS}
      size: 1Gi
    chartmuseum:
      storageClass: ${STORAGE_CLASS}
      size: 2Gi

# Enable ChartMuseum for npm packages
chartmuseum:
  enabled: true
  absoluteUrl: false
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

notary:
  enabled: false
trivy:
  enabled: false

# Minimal resource requirements
core:
  replicas: 1
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

jobservice:
  replicas: 1
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

registry:
  replicas: 1
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

portal:
  replicas: 1
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

nginx:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

database:
  internal:
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi

redis:
  internal:
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 100m
        memory: 128Mi
EOF

# Install Harbor
helm upgrade --install harbor harbor/harbor \
  -f /tmp/harbor-minimal-values.yaml \
  -n "$NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout 10m

# Create ingress
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

rm -f /tmp/harbor-minimal-values.yaml

echo "Harbor minimal installation complete!"
echo "URL: https://registry.${DOMAIN}"
echo "Username: admin"
echo "Password: $HARBOR_ADMIN_PASSWORD"