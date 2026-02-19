# 🚀 Quick Start - Deploy Any App in 60 Seconds

## Option 1: One-Click Deploy (Recommended)

Deploy any application with a single command:

```bash
cd /Volumes/dev/gmac-io-ci/deployment-system
./one-click-deploy.sh /path/to/your/app my-app-name
```

Example:
```bash
./one-click-deploy.sh ~/projects/my-node-app blog blog.gmac.io 3000
```

This will:
✅ Create Gitea repository  
✅ Add CI/CD workflow  
✅ Build Docker image  
✅ Deploy to Kubernetes  
✅ Configure SSL certificate  
✅ Set up monitoring  

## Option 2: Manual Quick Deploy

If you already have a Gitea repo:

```bash
./quick-deploy.sh <repo-name> <domain> <port>
```

Example:
```bash
./quick-deploy.sh my-api api.gmac.io 8080
```

## Option 3: Direct Deploy (No Git)

Deploy directly without Git:

```bash
./direct-deploy.sh <app-name> [domain] [image]
```

Example:
```bash
./direct-deploy.sh test-app test.gmac.io nginx:alpine
```

## 📝 All Credentials in One Place

```bash
# Source all credentials
source /Volumes/dev/gmac-io-ci/deployment-system/credentials.env

# Key URLs
- Gitea: https://git.gmac.io (user: gmackie)
- Harbor: https://registry.gmac.io (user: admin, pass: Harbor12345)
- ArgoCD: https://cd.gmac.io (user: admin)
- Grafana: https://grafana.gmac.io

# Quick logins
harbor_login    # Docker login to Harbor
argocd_login    # CLI login to ArgoCD
```

## 🎯 Common Tasks

### Deploy a Node.js App
```bash
# From your app directory
npx create-react-app my-app
cd my-app
/Volumes/dev/gmac-io-ci/deployment-system/one-click-deploy.sh . my-app
```

### Deploy a Python API
```bash
# From your Flask/FastAPI directory
echo "flask==2.3.0" > requirements.txt
/Volumes/dev/gmac-io-ci/deployment-system/one-click-deploy.sh . my-api api.gmac.io 5000
```

### Deploy Static Website
```bash
# From directory with index.html
/Volumes/dev/gmac-io-ci/deployment-system/one-click-deploy.sh . my-site site.gmac.io 80
```

## 🔍 Monitor Your Apps

```bash
# Watch pods deploy
kubectl get pods -A -w

# Check specific app
kubectl logs -n my-app -l app=my-app -f

# View all apps
kubectl get ingress -A
```

## ⚡ That's It!

Your app will be live at `https://your-domain.gmac.io` in 2-3 minutes!