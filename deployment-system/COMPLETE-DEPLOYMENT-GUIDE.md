# Complete Deployment Guide - gmac.io Kubernetes Cluster

This guide contains all credentials and instructions needed to deploy applications to the gmac.io Kubernetes cluster.

## 🔑 Credentials and API Keys

### Kubernetes Cluster
```bash
# Kubeconfig location
export KUBECONFIG=/Users/mackieg/.kube/config-hetzner

# Cluster IPs
MASTER_IP=5.78.106.236
WORKER_IP=5.78.125.172
```

### Gitea (Git Repository)
```bash
# URL
GITEA_URL=https://git.gmac.io

# Admin credentials
GITEA_USER=gmackie
GITEA_PASSWORD=<check-existing-secrets>

# API endpoint
GITEA_API=https://git.gmac.io/api/v1

# To create a new API token:
# 1. Login to https://git.gmac.io
# 2. Go to Settings > Applications
# 3. Generate New Token with repo permissions
```

### Harbor (Container Registry)
```bash
# Registry URL
HARBOR_URL=registry.gmac.io

# Admin credentials
HARBOR_USER=admin
HARBOR_PASSWORD=Harbor12345

# Docker login
docker login registry.gmac.io -u admin -p Harbor12345
```

### ArgoCD (GitOps Deployment)
```bash
# URL
ARGOCD_URL=https://cd.gmac.io

# Admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Login
argocd login cd.gmac.io --username admin --password $ARGOCD_PASSWORD --insecure
```

### Turso Database
```bash
# API Token
TURSO_TOKEN="eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJqdGkiOiI1WGRRT0pOZUVmQ1lieXBIQk9CQVVRIn0.gNVOOypsfbOcAeEvtEujJEDiR2gaN0auj_UecVfiAR7O3ZfOM_IzUg8bkhvcruqNeQAj2Fij9PB8i3-knYGvDw"

# Create database
turso db create my-app-db

# Get database URL
TURSO_DB_URL=$(turso db show my-app-db | grep URL | awk '{print $2}')
```

## 📦 Step-by-Step Deployment Process

### 1. Create Git Repository

```bash
# Create new repo on Gitea
curl -X POST https://git.gmac.io/api/v1/user/repos \
  -H "Authorization: token YOUR_GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-app",
    "private": false,
    "auto_init": true
  }'

# Add Gitea as remote to existing project
git remote add gitea https://git.gmac.io/gmackie/my-app.git
git push gitea main
```

### 2. Add GitHub Actions Workflow

Create `.github/workflows/deploy.yml` in your repository:

```yaml
name: Build and Deploy

on:
  push:
    branches: [ main, master ]

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Login to Harbor
        uses: docker/login-action@v2
        with:
          registry: registry.gmac.io
          username: admin
          password: Harbor12345
      
      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: registry.gmac.io/library/my-app:${{ github.sha }}
      
      - name: Update K8s manifest
        run: |
          sed -i "s|image: .*|image: registry.gmac.io/library/my-app:${{ github.sha }}|" k8s/deployment.yaml
          
      - name: Commit changes
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add k8s/deployment.yaml
          git commit -m "Update image to ${{ github.sha }}" || true
          git push
```

### 3. Create Kubernetes Manifests

Create `k8s/deployment.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      imagePullSecrets:
      - name: harbor-secret
      containers:
      - name: my-app
        image: registry.gmac.io/library/my-app:latest
        ports:
        - containerPort: 3000
        env:
        - name: TURSO_DB_URL
          valueFrom:
            secretKeyRef:
              name: my-app-secrets
              key: turso-db-url
        - name: TURSO_AUTH_TOKEN
          valueFrom:
            secretKeyRef:
              name: my-app-secrets
              key: turso-auth-token
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: my-app
spec:
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 3000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - my-app.gmac.io
    secretName: my-app-tls
  rules:
  - host: my-app.gmac.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

### 4. Create Secrets

```bash
# Create namespace
kubectl create namespace my-app

# Create Harbor pull secret
kubectl create secret docker-registry harbor-secret \
  --docker-server=registry.gmac.io \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n my-app

# Create Turso secrets
kubectl create secret generic my-app-secrets \
  --from-literal=turso-db-url="$TURSO_DB_URL" \
  --from-literal=turso-auth-token="$TURSO_TOKEN" \
  -n my-app
```

### 5. Setup ArgoCD Application

```bash
# Using the quick-deploy script
cd /Volumes/dev/gmac-io-ci/deployment-system
./quick-deploy.sh my-app my-app.gmac.io 3000

# OR manually create ArgoCD app
argocd app create my-app \
  --repo https://git.gmac.io/gmackie/my-app.git \
  --path k8s \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace my-app \
  --sync-policy automated \
  --self-heal
```

### 6. Deploy Application

```bash
# Push to trigger deployment
git add .
git commit -m "Initial deployment"
git push gitea main

# Monitor deployment
kubectl get pods -n my-app -w
argocd app get my-app
```

## 🚀 Quick Start Template

For new projects, use this one-liner to set up everything:

```bash
# Clone the deployment system
cd /Volumes/dev/gmac-io-ci/deployment-system

# Run the easy deploy wizard
./easy-deploy.sh

# Follow the prompts to:
# 1. Enter app name
# 2. Enter domain
# 3. Choose app type
# 4. Confirm deployment
```

## 🔧 Common Operations

### Update Application
```bash
# Make code changes
git add .
git commit -m "Update feature X"
git push gitea main
# ArgoCD will auto-sync within 3 minutes
```

### Manual Sync
```bash
argocd app sync my-app
```

### View Logs
```bash
kubectl logs -n my-app -l app=my-app -f
```

### Scale Application
```bash
kubectl scale deployment/my-app -n my-app --replicas=3
```

### Update Secrets
```bash
# Delete old secret
kubectl delete secret my-app-secrets -n my-app

# Create new secret
kubectl create secret generic my-app-secrets \
  --from-literal=new-key="new-value" \
  -n my-app

# Restart pods to pick up new secrets
kubectl rollout restart deployment/my-app -n my-app
```

## 📝 DNS Configuration

For new domains, add DNS record:
```
Type: A
Name: my-app
Value: 5.78.106.236
TTL: 300
```

## 🛠️ Troubleshooting

### Check deployment status
```bash
kubectl describe deployment -n my-app my-app
kubectl get events -n my-app --sort-by='.lastTimestamp'
```

### Check ingress
```bash
kubectl get ingress -n my-app
kubectl describe ingress -n my-app my-app
```

### Check certificates
```bash
kubectl get certificates -n my-app
kubectl describe certificate -n my-app my-app-tls
```

### Harbor login issues
```bash
# Test login
docker login registry.gmac.io -u admin -p Harbor12345

# Pull test
docker pull registry.gmac.io/library/my-app:latest
```

## 📋 Complete Example

Here's a complete Node.js app deployment:

```bash
# 1. Create local app
mkdir my-node-app && cd my-node-app
npm init -y
npm install express

# 2. Create app.js
cat > app.js << 'EOF'
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({ 
    message: 'Hello from Kubernetes!',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
EOF

# 3. Create Dockerfile
cat > Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["node", "app.js"]
EOF

# 4. Initialize git
git init
git add .
git commit -m "Initial commit"

# 5. Create Gitea repo and push
git remote add origin https://git.gmac.io/gmackie/my-node-app.git
git push -u origin main

# 6. Deploy using quick-deploy
cd /Volumes/dev/gmac-io-ci/deployment-system
./quick-deploy.sh my-node-app my-node-app.gmac.io 3000

# 7. Follow the output instructions to complete setup
```

## 🎯 Next Steps

1. **Monitor your app**: https://grafana.gmac.io
2. **View deployments**: https://cd.gmac.io
3. **Manage containers**: https://registry.gmac.io
4. **Check cluster health**: `kubectl top nodes`

## 📞 Support

- **Deployment System**: `/Volumes/dev/gmac-io-ci/deployment-system/`
- **Logs**: `kubectl logs -n <namespace> <pod>`
- **Events**: `kubectl get events -A --sort-by='.lastTimestamp'`