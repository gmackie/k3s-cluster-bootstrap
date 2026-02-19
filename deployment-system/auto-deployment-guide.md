# Auto-Deployment Guide for Gitea Repositories

This guide explains how to automatically deploy any application from your Gitea instance to the Kubernetes cluster with a custom domain.

## Quick Start

### Method 1: Using the Deploy Script (Recommended)

1. Make the deploy script executable:
```bash
chmod +x /tmp/deploy-app.sh
```

2. Run the script with your repository name and optional domain:
```bash
# Basic usage (uses repo-name.gmac.io)
./deploy-app.sh my-app

# With custom domain
./deploy-app.sh my-app my-custom-app.gmac.io

# With custom domain and port
./deploy-app.sh my-app my-custom-app.gmac.io 8080
```

3. The script will:
   - Clone your repository
   - Add a GitHub Actions workflow
   - Create an ArgoCD application
   - Set up automatic deployment

4. Push any change to trigger deployment:
```bash
cd /path/to/your/repo
echo "# Trigger deployment" >> README.md
git add . && git commit -m "Trigger initial deployment"
git push
```

### Method 2: Manual Setup

1. Copy the workflow file to your repository:
```bash
mkdir -p .github/workflows
cp /tmp/.github-workflow-template.yml .github/workflows/deploy.yml
```

2. Edit the workflow file and set:
   - `APP_DOMAIN`: Your desired domain (e.g., `my-app.gmac.io`)
   - `APP_PORT`: Your application port (default: 3000)

3. Commit and push:
```bash
git add .github/workflows/deploy.yml
git commit -m "Add deployment workflow"
git push
```

## How It Works

### 1. Automatic Dockerfile Detection

The workflow automatically detects your application type and creates an appropriate Dockerfile:

- **Node.js** (detected by `package.json`): Multi-stage build with npm
- **Python** (detected by `requirements.txt`): Python slim image
- **Go** (detected by `go.mod`): Multi-stage build with Alpine
- **Static files**: Nginx server (default)

### 2. Image Building and Registry

- Images are built automatically on push to main/master
- Pushed to Harbor at `registry.gmac.io/apps/<repo-name>`
- Tagged with commit SHA and `latest`

### 3. Kubernetes Manifests

The workflow generates:
- **Deployment**: Runs your application with resource limits
- **Service**: Internal cluster networking
- **Ingress**: HTTPS with Let's Encrypt SSL certificate

### 4. ArgoCD Integration

- Automatically creates/updates ArgoCD application
- Syncs changes within minutes
- Self-healing enabled (reverts manual changes)

## Configuration Options

### Environment Variables in Workflow

```yaml
env:
  APP_NAME: my-app           # Repository name
  APP_DOMAIN: my-app.gmac.io # Your domain
  APP_PORT: "3000"          # Application port
  REGISTRY: registry.gmac.io # Harbor registry
  REGISTRY_NAMESPACE: apps   # Registry namespace
```

### Custom Dockerfile

If the auto-detection doesn't work for your app, create a `Dockerfile` in your repository root:

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY . .
RUN npm install
EXPOSE 3000
CMD ["node", "server.js"]
```

### Resource Limits

Default limits in the generated manifests:
- CPU: 50m-500m
- Memory: 128Mi-512Mi

To customize, edit the generated `k8s/deployment.yaml`.

### Multiple Environments

For staging/production setups, use branches:

```yaml
on:
  push:
    branches: 
      - main     # Production
      - staging  # Staging
```

## Using Helm Charts (Advanced)

For more complex applications, use the generic Helm chart:

1. Copy the chart to your repo:
```bash
cp -r /tmp/generic-app-chart ./charts/
```

2. Create a values file:
```yaml
# values-prod.yaml
image:
  repository: registry.gmac.io/apps/my-app
  tag: latest

ingress:
  hosts:
    - host: my-app.gmac.io
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: my-app-tls
      hosts:
        - my-app.gmac.io
```

3. Update the workflow to use Helm:
```yaml
- name: Deploy with Helm
  run: |
    helm template my-app ./charts/generic-app-chart \
      -f values-prod.yaml \
      --set image.tag=${{ steps.vars.outputs.tag }} \
      > k8s/all.yaml
```

## DNS Configuration

Ensure your domain points to the cluster:

1. For `*.gmac.io` subdomains: Already configured
2. For custom domains: Add A record pointing to cluster IP

## Monitoring Your Deployment

### ArgoCD UI
- Visit: https://argocd.gmac.io
- Find your application
- Check sync status and logs

### Kubectl Commands
```bash
# Check deployment status
kubectl get deploy -n <app-name>

# View pods
kubectl get pods -n <app-name>

# Check logs
kubectl logs -n <app-name> -l app=<app-name>

# Describe ingress
kubectl describe ingress -n <app-name>
```

## Troubleshooting

### Image Build Fails
- Check Gitea Actions runner logs
- Ensure Dockerfile is valid
- Check Harbor credentials

### Application Not Accessible
1. Check ingress status:
   ```bash
   kubectl get ingress -n <app-name>
   ```

2. Check certificate:
   ```bash
   kubectl get certificate -n <app-name>
   ```

3. Check pod status:
   ```bash
   kubectl get pods -n <app-name>
   ```

### ArgoCD Sync Issues
- Check ArgoCD application status
- Verify repository access
- Check for YAML syntax errors

## Best Practices

1. **Health Checks**: Ensure your app responds to `/` for health probes
2. **Port Configuration**: Use `PORT` environment variable
3. **Graceful Shutdown**: Handle SIGTERM for zero-downtime deploys
4. **Secrets**: Use Kubernetes secrets, not hardcoded values
5. **Resource Limits**: Adjust based on actual usage

## Example Applications

### Node.js Express
```javascript
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.send('Hello World!');
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
```

### Python Flask
```python
from flask import Flask
import os

app = Flask(__name__)
port = int(os.environ.get('PORT', 3000))

@app.route('/')
def hello():
    return 'Hello World!'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=port)
```

### Static HTML
```html
<!DOCTYPE html>
<html>
<head>
    <title>My App</title>
</head>
<body>
    <h1>Hello from Kubernetes!</h1>
</body>
</html>
```

## Security Considerations

1. **Registry Access**: Runners have read/write access to Harbor
2. **Ingress**: All apps get HTTPS by default
3. **Network Policies**: Consider adding for production
4. **RBAC**: Apps run in isolated namespaces

## Cleanup

To remove a deployed application:

```bash
# Delete ArgoCD application (this removes all resources)
kubectl delete application -n argocd <app-name>

# Or manually delete namespace
kubectl delete namespace <app-name>
```