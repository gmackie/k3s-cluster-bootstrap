#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if required arguments are provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <repository-name> [domain] [port]"
    echo "Example: $0 my-app my-app.gmac.io 3000"
    echo "         $0 my-app  # Uses my-app.gmac.io and port 3000 by default"
    exit 1
fi

REPO_NAME=$1
DOMAIN=${2:-"${REPO_NAME}.gmac.io"}
PORT=${3:-"3000"}
GITEA_URL="https://git.gmac.io"
GITEA_USER="gmackie"

print_info "Deploying application: $REPO_NAME"
print_info "Domain: $DOMAIN"
print_info "Port: $PORT"

# Clone the repository
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

print_info "Cloning repository..."
if ! git clone "${GITEA_URL}/${GITEA_USER}/${REPO_NAME}.git" .; then
    print_error "Failed to clone repository. Make sure the repository exists."
    exit 1
fi

# Create .github/workflows directory
mkdir -p .github/workflows

# Copy workflow template and customize it
print_info "Adding GitHub Actions workflow..."
cat > .github/workflows/deploy.yml << EOF
name: Build and Deploy

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]

env:
  APP_NAME: ${REPO_NAME}
  APP_DOMAIN: ${DOMAIN}
  APP_PORT: "${PORT}"
  REGISTRY: registry.gmac.io
  REGISTRY_NAMESPACE: apps

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Generate deployment vars
      id: vars
      run: |
        echo "domain=\${{ env.APP_DOMAIN }}" >> \$GITHUB_OUTPUT
        echo "image=\${{ env.REGISTRY }}/\${{ env.REGISTRY_NAMESPACE }}/\${{ env.APP_NAME }}" >> \$GITHUB_OUTPUT
        echo "tag=\${GITHUB_SHA::8}" >> \$GITHUB_OUTPUT

    - name: Build and push Docker image
      run: |
        # Check if Dockerfile exists, if not create a default one
        if [ ! -f Dockerfile ]; then
          echo "No Dockerfile found, detecting application type..."
          
          if [ -f package.json ]; then
            echo "Detected Node.js application"
            cat > Dockerfile << 'DOCKERFILE'
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build || true

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app .
EXPOSE \${{ env.APP_PORT }}
CMD ["npm", "start"]
DOCKERFILE
          elif [ -f requirements.txt ]; then
            echo "Detected Python application"
            cat > Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE \${{ env.APP_PORT }}
CMD ["python", "app.py"]
DOCKERFILE
          elif [ -f go.mod ]; then
            echo "Detected Go application"
            cat > Dockerfile << 'DOCKERFILE'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY . .
RUN go build -o app .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/app .
EXPOSE \${{ env.APP_PORT }}
CMD ["./app"]
DOCKERFILE
          else
            echo "Could not detect application type, using generic static file server"
            cat > Dockerfile << 'DOCKERFILE'
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 80
DOCKERFILE
            echo "APP_PORT=80" >> \$GITHUB_ENV
          fi
        fi
        
        # Build and push image
        docker build -t \${{ steps.vars.outputs.image }}:\${{ steps.vars.outputs.tag }} .
        docker tag \${{ steps.vars.outputs.image }}:\${{ steps.vars.outputs.tag }} \${{ steps.vars.outputs.image }}:latest
        docker push \${{ steps.vars.outputs.image }}:\${{ steps.vars.outputs.tag }}
        docker push \${{ steps.vars.outputs.image }}:latest

    - name: Generate Kubernetes manifests
      run: |
        mkdir -p k8s
        
        # Generate deployment manifest
        cat > k8s/deployment.yaml << YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: \${{ env.APP_NAME }}
  labels:
    app: \${{ env.APP_NAME }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: \${{ env.APP_NAME }}
  template:
    metadata:
      labels:
        app: \${{ env.APP_NAME }}
    spec:
      containers:
      - name: \${{ env.APP_NAME }}
        image: \${{ steps.vars.outputs.image }}:\${{ steps.vars.outputs.tag }}
        ports:
        - containerPort: \${{ env.APP_PORT }}
          name: http
        env:
        - name: PORT
          value: "\${{ env.APP_PORT }}"
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
YAML
        
        # Generate service manifest
        cat > k8s/service.yaml << YAML
apiVersion: v1
kind: Service
metadata:
  name: \${{ env.APP_NAME }}
spec:
  type: ClusterIP
  selector:
    app: \${{ env.APP_NAME }}
  ports:
  - port: 80
    targetPort: http
    protocol: TCP
YAML
        
        # Generate ingress manifest
        cat > k8s/ingress.yaml << YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: \${{ env.APP_NAME }}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - \${{ steps.vars.outputs.domain }}
    secretName: \${{ env.APP_NAME }}-tls
  rules:
  - host: \${{ steps.vars.outputs.domain }}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: \${{ env.APP_NAME }}
            port:
              number: 80
YAML

    - name: Commit deployment manifests
      run: |
        git config user.name "GitHub Actions"
        git config user.email "actions@gmac.io"
        git add k8s/
        git diff --staged --quiet || git commit -m "Update deployment manifests for \${{ steps.vars.outputs.tag }}"
        git push
EOF

# Commit and push the workflow
print_info "Committing workflow..."
git add .github/workflows/deploy.yml
git commit -m "Add automated deployment workflow for $DOMAIN" || true
git push

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
    syncOptions:
    - CreateNamespace=true
EOF

# Apply ArgoCD application
if command -v kubectl &> /dev/null; then
    print_info "Applying ArgoCD application..."
    KUBECONFIG=/Users/mackieg/.kube/config-hetzner kubectl apply -f /tmp/argocd-app-${REPO_NAME}.yaml
else
    print_info "kubectl not found. Please apply the following manually:"
    cat /tmp/argocd-app-${REPO_NAME}.yaml
fi

# Clean up
cd /
rm -rf $TEMP_DIR

print_success "Deployment setup complete!"
print_info "The application will be deployed automatically on the next push to main/master branch"
print_info "It will be available at: https://${DOMAIN}"
print_info ""
print_info "To trigger deployment now, make any change to the repository and push it."
print_info "To check deployment status, visit: https://argocd.gmac.io"