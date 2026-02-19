#!/bin/bash
# Simple Control Panel installation

source "${SCRIPT_DIR}/lib/common.sh"

info "Installing Simple Control Panel..."

# Configuration
NAMESPACE="control-panel"
DOMAIN="${DOMAIN:-control.gmac.io}"
DOMAIN_NAME="${DOMAIN_NAME:-gmac.io}"

# Create namespace
ensure_namespace control-panel

# Deploy the simple control panel
info "Deploying control panel..."
sed -e "s/\${DOMAIN_NAME}/${DOMAIN_NAME}/g" "${SCRIPT_DIR}/control-panel-simple.yaml" | kubectl apply -f -

# Wait for deployment
wait_for_deployment control-panel control-panel

# The ingress is already configured in the main install script
# Just update it if needed
if kubectl get ingress control-panel -n control-panel &>/dev/null; then
    info "Ingress already exists, updating..."
else
    info "Creating ingress..."
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: control-panel
  namespace: ${NAMESPACE}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    # OAuth2 annotations
    nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.auth-system.svc.cluster.local:4180/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://${DOMAIN_NAME}/oauth2/start?rd=\$scheme://\$host\$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Access-Token"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - control.${DOMAIN_NAME}
    secretName: control-panel-tls
  rules:
  - host: control.${DOMAIN_NAME}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: control-panel
            port:
              number: 80
EOF
fi

success "Simple Control Panel installed successfully!"
info "Access Control Panel at: https://control.${DOMAIN_NAME}"