# 🚀 Gitea to Kubernetes Auto-Deployment System

## Overview

This system allows you to deploy any Gitea repository to your Kubernetes cluster with a single command. It automatically:

- ✅ Detects application type (Node.js, Python, Go, static files)
- ✅ Builds Docker images and pushes to Harbor
- ✅ Generates Kubernetes manifests
- ✅ Creates ArgoCD applications for GitOps
- ✅ Provisions SSL certificates
- ✅ Sets up custom domains

## Installation

Run the setup script:
```bash
chmod +x /tmp/deployment-system-setup.sh
/tmp/deployment-system-setup.sh
```

## Usage

### Interactive Mode (Easiest)
```bash
deploy-app
```
This will:
1. List all your repositories
2. Let you choose one
3. Ask for domain and port
4. Deploy automatically

### Command Line Mode
```bash
# Use default domain (repo-name.gmac.io)
deploy-app my-app

# Custom domain
deploy-app my-app my-app.example.com

# Custom domain and port
deploy-app my-app my-app.example.com 8080
```

## How It Works

### 1. Repository Setup
The tool adds a `.github/workflows/deploy.yml` file to your repository that:
- Triggers on push to main/master
- Detects your application type
- Builds appropriate Docker image

### 2. Automatic Dockerfile Generation

If no Dockerfile exists, the system creates one based on your project:

| File Detected | Application Type | Base Image |
|--------------|------------------|------------|
| package.json | Node.js | node:18-alpine |
| requirements.txt | Python | python:3.11-slim |
| go.mod | Go | golang:1.21-alpine |
| None | Static | nginx:alpine |

### 3. Image Registry

Images are pushed to Harbor:
- Registry: `registry.gmac.io`
- Namespace: `apps`
- Format: `registry.gmac.io/apps/<repo-name>:<tag>`

### 4. Kubernetes Resources

Generated automatically:
- **Deployment**: Runs your app with health checks
- **Service**: Internal networking
- **Ingress**: HTTPS with automatic SSL

### 5. ArgoCD Integration

- Creates ArgoCD application
- Auto-sync enabled
- Self-healing (reverts manual changes)
- Monitors Git for changes

## Example Workflow

1. **Create a simple Node.js app**:
```bash
mkdir my-node-app
cd my-node-app

cat > package.json << 'EOF'
{
  "name": "my-node-app",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  }
}
EOF

cat > server.js << 'EOF'
const http = require('http');
const port = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'text/html'});
  res.end('<h1>Hello from Kubernetes!</h1>');
});

server.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
EOF
```

2. **Initialize Git and push to Gitea**:
```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin https://git.gmac.io/gmackie/my-node-app.git
git push -u origin main
```

3. **Deploy the app**:
```bash
deploy-app my-node-app my-node-app.gmac.io
```

4. **Trigger deployment**:
```bash
echo "# Deployed!" >> README.md
git add . && git commit -m "Trigger deployment"
git push
```

5. **Access your app**:
- Wait 2-3 minutes for initial deployment
- Visit: https://my-node-app.gmac.io

## Advanced Configuration

### Custom Dockerfile

Create a `Dockerfile` in your repository:
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

### Environment Variables

Add to the workflow:
```yaml
env:
  NODE_ENV: production
  DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

### Resource Limits

Edit `k8s/deployment.yaml` after generation:
```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

### Health Checks

Customize in the deployment:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
```

## Monitoring

### ArgoCD Dashboard
- URL: https://argocd.gmac.io
- View application status
- Check sync status
- View logs

### Kubectl Commands
```bash
# List all auto-deployed apps
kubectl get applications -n argocd -l auto-deployed=true

# Check app status
kubectl get all -n <app-name>

# View logs
kubectl logs -n <app-name> -l app=<app-name>

# Describe ingress
kubectl describe ingress -n <app-name>
```

## Troubleshooting

### Build Failures
1. Check Gitea Actions:
   - Go to repository → Actions tab
   - View workflow runs
   - Check logs

2. Common issues:
   - Missing dependencies in package.json
   - Syntax errors in code
   - Wrong Node.js version

### Deployment Issues
1. Check ArgoCD:
   ```bash
   kubectl describe application -n argocd <app-name>
   ```

2. Check pods:
   ```bash
   kubectl get pods -n <app-name>
   kubectl describe pod -n <app-name> <pod-name>
   ```

### SSL Certificate Issues
1. Check cert-manager:
   ```bash
   kubectl get certificate -n <app-name>
   kubectl describe certificate -n <app-name>
   ```

2. Check ingress:
   ```bash
   kubectl get ingress -n <app-name>
   ```

### Application Not Starting
1. Check logs:
   ```bash
   kubectl logs -n <app-name> -l app=<app-name>
   ```

2. Common issues:
   - Wrong PORT environment variable
   - Missing dependencies
   - Database connection errors

## Best Practices

1. **Use Environment Variables**
   - Don't hardcode sensitive data
   - Use Kubernetes secrets
   - Example:
   ```javascript
   const port = process.env.PORT || 3000;
   const dbUrl = process.env.DATABASE_URL;
   ```

2. **Implement Health Checks**
   ```javascript
   app.get('/health', (req, res) => {
     res.status(200).json({ status: 'healthy' });
   });
   ```

3. **Handle Graceful Shutdown**
   ```javascript
   process.on('SIGTERM', () => {
     server.close(() => {
       console.log('Process terminated');
     });
   });
   ```

4. **Use Multi-stage Builds**
   - Reduces image size
   - Improves security
   - Faster deployments

5. **Set Resource Limits**
   - Prevents resource exhaustion
   - Ensures fair resource sharing
   - Helps cluster stability

## Security

1. **Image Scanning**
   - Harbor scans all images
   - View vulnerabilities in Harbor UI

2. **Network Policies**
   - Consider adding for production
   - Restrict inter-pod communication

3. **RBAC**
   - Each app runs in its own namespace
   - Limited permissions by default

4. **Secrets Management**
   - Use Kubernetes secrets
   - Consider Sealed Secrets for GitOps

## Cleanup

Remove a deployed application:
```bash
# Via ArgoCD (recommended)
kubectl delete application -n argocd <app-name>

# Manual cleanup
kubectl delete namespace <app-name>
```

## Integration Points

### CI/CD Pipeline
- Gitea Actions (GitHub Actions compatible)
- Automated testing before deployment
- Multi-environment deployments

### Monitoring
- Prometheus metrics
- Grafana dashboards
- Application logs

### Registry
- Harbor for container images
- Vulnerability scanning
- Image signing

## Next Steps

1. **Add more apps**: Use `deploy-app` for each repository
2. **Custom domains**: Point DNS to cluster IP
3. **Monitoring**: Set up alerts for your apps
4. **Scaling**: Enable horizontal pod autoscaling
5. **Backups**: Configure persistent volume backups

## Support

- Documentation: `/opt/gmac-deploy/auto-deployment-guide.md`
- ArgoCD: https://argocd.gmac.io
- Harbor: https://registry.gmac.io
- Gitea: https://git.gmac.io