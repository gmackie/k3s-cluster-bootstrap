#!/bin/bash
set -euo pipefail

# One-click deployment script with all credentials embedded

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Load all credentials
source "$(dirname "$0")/credentials.env"

# Check parameters
if [ $# -lt 2 ]; then
    cat << EOF
${YELLOW}One-Click Kubernetes Deployment${NC}

Usage: $0 <git-repo-path> <app-name> [domain] [port]

Examples:
  $0 ./my-node-app my-app                    # Uses my-app.gmac.io, port 3000
  $0 ./my-python-api api api.gmac.io 8080    # Custom domain and port
  $0 ~/projects/web-app prod-web             # Deploy from any directory

This script will:
1. Create a Gitea repository
2. Add GitHub Actions workflow
3. Build and push Docker image
4. Deploy to Kubernetes with ArgoCD
5. Configure ingress with SSL

EOF
    exit 1
fi

REPO_PATH=$(realpath "$1")
APP_NAME=$2
DOMAIN=${3:-"${APP_NAME}.gmac.io"}
PORT=${4:-3000}

print_info "🚀 One-Click Deployment Configuration:"
print_info "  Repository: $REPO_PATH"
print_info "  App Name: $APP_NAME"
print_info "  Domain: $DOMAIN"
print_info "  Port: $PORT"
echo

# Change to repo directory
cd "$REPO_PATH"

# Initialize git if needed
if [ ! -d .git ]; then
    print_info "Initializing git repository..."
    git init
    git add .
    git commit -m "Initial commit" || true
fi

# Create Gitea repository
print_info "Creating Gitea repository..."
CREATE_REPO_RESPONSE=$(curl -s -X POST $GITEA_API/user/repos \
  -H "Content-Type: application/json" \
  -u "$GITEA_USER:$GITEA_PASSWORD" \
  -d "{
    \"name\": \"$APP_NAME\",
    \"private\": false,
    \"auto_init\": false
  }")

if echo "$CREATE_REPO_RESPONSE" | grep -q "already exists"; then
    print_warning "Repository already exists, continuing..."
else
    print_success "Repository created"
fi

# Add Gitea remote
git remote remove gitea 2>/dev/null || true
git remote add gitea "$GITEA_URL/$GITEA_USER/$APP_NAME.git"

# Create GitHub Actions workflow
print_info "Creating GitHub Actions workflow..."
mkdir -p .github/workflows
cat > .github/workflows/deploy.yml << EOF
name: Build and Deploy

on:
  push:
    branches: [ main, master ]

env:
  REGISTRY: $HARBOR_URL
  IMAGE_NAME: library/$APP_NAME

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Detect application type
        id: detect
        run: |
          if [ -f package.json ]; then
            echo "type=node" >> \$GITHUB_OUTPUT
          elif [ -f requirements.txt ] || [ -f setup.py ] || [ -f Pipfile ]; then
            echo "type=python" >> \$GITHUB_OUTPUT
          elif [ -f go.mod ]; then
            echo "type=go" >> \$GITHUB_OUTPUT
          elif [ -f index.html ] || [ -f index.htm ]; then
            echo "type=static" >> \$GITHUB_OUTPUT
          else
            echo "type=generic" >> \$GITHUB_OUTPUT
          fi
      
      - name: Create Dockerfile if missing
        run: |
          if [ ! -f Dockerfile ]; then
            case "\${{ steps.detect.outputs.type }}" in
              node)
                cat > Dockerfile << 'DOCKERFILE'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production || npm install
COPY . .
EXPOSE $PORT
CMD ["npm", "start"]
DOCKERFILE
                ;;
              python)
                cat > Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt* setup.py* Pipfile* ./
RUN pip install --no-cache-dir -r requirements.txt 2>/dev/null || \
    pip install --no-cache-dir . 2>/dev/null || \
    pip install pipenv && pipenv install --system --deploy 2>/dev/null || true
COPY . .
EXPOSE $PORT
CMD ["python", "app.py"]
DOCKERFILE
                ;;
              go)
                cat > Dockerfile << 'DOCKERFILE'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY . .
RUN go build -o main .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/main .
EXPOSE $PORT
CMD ["./main"]
DOCKERFILE
                ;;
              static)
                cat > Dockerfile << 'DOCKERFILE'
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 80
DOCKERFILE
                ;;
              *)
                cat > Dockerfile << 'DOCKERFILE'
FROM ubuntu:22.04
WORKDIR /app
COPY . .
EXPOSE $PORT
CMD ["/bin/bash", "-c", "echo 'Please provide a proper start command'"]
DOCKERFILE
                ;;
            esac
          fi
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Login to Harbor
        uses: docker/login-action@v2
        with:
          registry: \${{ env.REGISTRY }}
          username: $HARBOR_USER
          password: $HARBOR_PASSWORD
      
      - name: Build and push Docker image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            \${{ env.REGISTRY }}/\${{ env.IMAGE_NAME }}:latest
            \${{ env.REGISTRY }}/\${{ env.IMAGE_NAME }}:\${{ github.sha }}
      
      - name: Update Kubernetes manifest
        run: |
          mkdir -p k8s
          cat > k8s/deployment.yaml << 'K8S'
apiVersion: v1
kind: Namespace
metadata:
  name: $APP_NAME
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  namespace: $APP_NAME
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      imagePullSecrets:
      - name: harbor-secret
      containers:
      - name: $APP_NAME
        image: $HARBOR_URL/library/$APP_NAME:\${{ github.sha }}
        ports:
        - containerPort: $PORT
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /health
            port: $PORT
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: $PORT
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
  namespace: $APP_NAME
spec:
  selector:
    app: $APP_NAME
  ports:
  - port: 80
    targetPort: $PORT
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $APP_NAME
  namespace: $APP_NAME
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - $DOMAIN
    secretName: $APP_NAME-tls
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
K8S
          
      - name: Commit and push changes
        run: |
          git config --global user.name "GitHub Actions"
          git config --global user.email "actions@github.com"
          git add k8s/deployment.yaml Dockerfile
          git diff --cached --quiet || git commit -m "Update deployment to \${{ github.sha }}"
          git push origin HEAD
EOF

# Create initial Kubernetes manifest
mkdir -p k8s
cp .github/workflows/deploy.yml k8s/deployment.yaml.template

# Create secrets
print_info "Creating Kubernetes secrets..."
kubectl create namespace $APP_NAME --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret docker-registry harbor-secret \
    --docker-server=$HARBOR_URL \
    --docker-username=$HARBOR_USER \
    --docker-password=$HARBOR_PASSWORD \
    -n $APP_NAME --dry-run=client -o yaml | kubectl apply -f -

# Create ArgoCD application
print_info "Creating ArgoCD application..."
cat > /tmp/argocd-app-${APP_NAME}.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${GITEA_URL}/${GITEA_USER}/${APP_NAME}.git
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: ${APP_NAME}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

kubectl apply -f /tmp/argocd-app-${APP_NAME}.yaml

# Commit and push
print_info "Pushing to Gitea..."
git add -A
git commit -m "Add deployment configuration" || true
git push -f gitea main

print_success "Deployment initiated!"
print_info ""
print_info "📋 Next Steps:"
print_info "1. Monitor build progress in Gitea Actions"
print_info "2. Check deployment: kubectl get pods -n $APP_NAME"
print_info "3. View in ArgoCD: $ARGOCD_URL/applications/$APP_NAME"
print_info "4. Access app: https://$DOMAIN (may take 2-3 minutes for SSL)"
print_info ""
print_info "🔍 Useful Commands:"
echo "   kubectl logs -n $APP_NAME -l app=$APP_NAME -f"
echo "   kubectl get ingress -n $APP_NAME"
echo "   argocd app sync $APP_NAME"
echo "   curl -k https://$DOMAIN"