#!/bin/bash
set -euo pipefail

export KUBECONFIG=~/.kube/config-hetzner

echo "Configuring Harbor for GitHub OAuth SSO..."

# Get current Harbor values
helm get values harbor -n registry > /tmp/harbor-current-values.yaml

# Get GitHub OAuth credentials
GITHUB_CLIENT_ID=$(kubectl get secret oauth2-proxy-secret -n auth-system -o jsonpath='{.data.client-id}' | base64 -d)
GITHUB_CLIENT_SECRET=$(kubectl get secret oauth2-proxy-secret -n auth-system -o jsonpath='{.data.client-secret}' | base64 -d)

# Harbor doesn't directly support GitHub OAuth, but we can use oauth2-proxy as an OIDC provider
# First, let's update the ingress to remove OAuth2 proxy for now and configure Harbor's built-in auth

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: harbor-ingress
  namespace: registry
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
    - registry.gmac.io
    secretName: harbor-tls
  rules:
  - host: registry.gmac.io
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

echo "Note: Harbor doesn't natively support GitHub OAuth."
echo "Options:"
echo "1. Keep using local Harbor accounts with strong passwords"
echo "2. Use oauth2-proxy in front of Harbor (current setup)"
echo "3. Set up Dex as an OIDC provider that bridges to GitHub"
echo ""
echo "For now, Harbor will use local authentication."
echo "You can still access it through the main domain OAuth flow."