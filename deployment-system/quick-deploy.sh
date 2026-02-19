#!/bin/bash
set -euo pipefail

# Quick deploy script that just creates ArgoCD app without cloning

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ $# -lt 1 ]; then
    echo "Usage: $0 <repository-name> [domain] [port]"
    echo "Example: $0 my-app my-app.gmac.io 3000"
    exit 1
fi

REPO_NAME=$1
DOMAIN=${2:-"${REPO_NAME}.gmac.io"}
PORT=${3:-"3000"}
GITEA_URL="https://git.gmac.io"
GITEA_USER="gmackie"
KUBECONFIG_PATH="/Users/mackieg/.kube/config-hetzner"

print_info "Quick Deploy for: $REPO_NAME"
print_info "Domain: $DOMAIN"
print_info "Port: $PORT"

# Create ArgoCD application
print_info "Creating ArgoCD application..."
cat > /tmp/argocd-app-${REPO_NAME}.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${REPO_NAME}
  namespace: argocd
  labels:
    app.kubernetes.io/name: ${REPO_NAME}
    auto-deploy: "true"
  annotations:
    deployment.gmac.io/domain: "${DOMAIN}"
    deployment.gmac.io/port: "${PORT}"
spec:
  project: default
  source:
    repoURL: ${GITEA_URL}/${GITEA_USER}/${REPO_NAME}
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: ${REPO_NAME}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

# Apply ArgoCD application
print_info "Applying ArgoCD application..."
KUBECONFIG=$KUBECONFIG_PATH kubectl apply -f /tmp/argocd-app-${REPO_NAME}.yaml

# Create deployment instructions
cat > /tmp/deploy-instructions-${REPO_NAME}.md << EOF
# Deployment Instructions for ${REPO_NAME}

Your ArgoCD application has been created. Now add these files to your repository:

## 1. Create .github/workflows/deploy.yml

\`\`\`yaml
name: Build and Deploy

on:
  push:
    branches: [ main, master ]

env:
  APP_NAME: ${REPO_NAME}
  APP_DOMAIN: ${DOMAIN}
  APP_PORT: "${PORT}"
  REGISTRY: registry.gmac.io
  REGISTRY_NAMESPACE: apps

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Build and push Docker image
      run: |
        # Auto-detect Dockerfile or create one
        if [ ! -f Dockerfile ]; then
          if [ -f package.json ]; then
            cat > Dockerfile << 'DOCKERFILE'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci || npm install
COPY . .
EXPOSE ${PORT}
CMD ["npm", "start"]
DOCKERFILE
          elif [ -f requirements.txt ]; then
            cat > Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
EXPOSE ${PORT}
CMD ["python", "app.py"]
DOCKERFILE
          fi
        fi
        
        docker build -t \${{ env.REGISTRY }}/\${{ env.REGISTRY_NAMESPACE }}/\${{ env.APP_NAME }}:latest .
        docker push \${{ env.REGISTRY }}/\${{ env.REGISTRY_NAMESPACE }}/\${{ env.APP_NAME }}:latest
\`\`\`

## 2. Create k8s/deployment.yaml

\`\`\`yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${REPO_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${REPO_NAME}
  template:
    metadata:
      labels:
        app: ${REPO_NAME}
    spec:
      containers:
      - name: ${REPO_NAME}
        image: registry.gmac.io/apps/${REPO_NAME}:latest
        ports:
        - containerPort: ${PORT}
        env:
        - name: PORT
          value: "${PORT}"
---
apiVersion: v1
kind: Service
metadata:
  name: ${REPO_NAME}
spec:
  selector:
    app: ${REPO_NAME}
  ports:
  - port: 80
    targetPort: ${PORT}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${REPO_NAME}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - ${DOMAIN}
    secretName: ${REPO_NAME}-tls
  rules:
  - host: ${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${REPO_NAME}
            port:
              number: 80
\`\`\`

## 3. Push to trigger deployment

\`\`\`bash
git add .github/workflows/deploy.yml k8s/
git commit -m "Add deployment configuration"
git push
\`\`\`

Your application will be available at: https://${DOMAIN}
EOF

print_success "ArgoCD application created!"
print_info "Instructions saved to: /tmp/deploy-instructions-${REPO_NAME}.md"
print_info ""
print_info "Next steps:"
print_info "1. Add the deployment files to your repository (see instructions)"
print_info "2. Push to trigger deployment"
print_info "3. Monitor at: https://argocd.gmac.io/applications/${REPO_NAME}"
print_info ""
print_info "Quick add files:"
echo "cat /tmp/deploy-instructions-${REPO_NAME}.md"