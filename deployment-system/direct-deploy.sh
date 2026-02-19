#!/bin/bash
set -euo pipefail

# Direct deployment script that creates all resources without Git dependency

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ $# -lt 1 ]; then
    echo "Usage: $0 <app-name> [domain] [image]"
    echo "Example: $0 my-app my-app.gmac.io nginx:alpine"
    exit 1
fi

APP_NAME=$1
DOMAIN=${2:-"${APP_NAME}.gmac.io"}
IMAGE=${3:-"nginx:alpine"}
NAMESPACE=$APP_NAME
KUBECONFIG_PATH="/Users/mackieg/.kube/config-hetzner"

print_info "Direct Deploy Configuration:"
print_info "  App Name: $APP_NAME"
print_info "  Domain: $DOMAIN"
print_info "  Image: $IMAGE"
print_info "  Namespace: $NAMESPACE"

# Create namespace
print_info "Creating namespace..."
KUBECONFIG=$KUBECONFIG_PATH kubectl create namespace $NAMESPACE --dry-run=client -o yaml | KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f -

# Create deployment
print_info "Creating deployment..."
cat << EOF | KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
    app: $APP_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
      - name: $APP_NAME
        image: $IMAGE
        ports:
        - containerPort: 80
          name: http
        env:
        - name: APP_NAME
          value: "$APP_NAME"
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

# Create service
print_info "Creating service..."
cat << EOF | KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
    app: $APP_NAME
spec:
  type: ClusterIP
  selector:
    app: $APP_NAME
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
EOF

# Create ingress
print_info "Creating ingress..."
cat << EOF | KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $APP_NAME
  namespace: $NAMESPACE
  labels:
    app: $APP_NAME
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: $DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $APP_NAME
            port:
              number: 80
EOF

print_success "Deployment complete!"
print_info ""
print_info "Check status:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl get ingress -n $NAMESPACE"
print_info ""
print_info "Application will be available at:"
echo "  http://$DOMAIN"
print_info ""
print_info "To add SSL later:"
echo "  kubectl annotate ingress -n $NAMESPACE $APP_NAME cert-manager.io/cluster-issuer=letsencrypt-prod"