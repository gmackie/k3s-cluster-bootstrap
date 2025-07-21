# Setting Up Gitea Secrets for K3s Deployment

## Required Secrets

Each repository needs these secrets to deploy to k3s:

### 1. KUBECONFIG
The base64-encoded kubeconfig file for accessing your k3s cluster.

**Already prepared in:** `kubeconfig-base64.txt`

### 2. GITEA_TOKEN  
Your Gitea API token for pushing Docker images to the registry.

**Your token:** `6c0c69be9e3ac745fd234a47e276df22955268ba`

## How to Add Secrets to a Repository

1. Go to your repository in Gitea (e.g., https://ci.gmac.io/mackieg/your-repo)
2. Click **Settings** → **Actions** → **Secrets**
3. Click **Add Secret**

### Add KUBECONFIG Secret:
- **Name:** `KUBECONFIG`
- **Value:** Copy entire contents of `kubeconfig-base64.txt`

### Add GITEA_TOKEN Secret:
- **Name:** `GITEA_TOKEN`
- **Value:** `6c0c69be9e3ac745fd234a47e276df22955268ba`

## Workflow Setup

1. Create `.gitea/workflows/` directory in your repo
2. Copy the appropriate workflow file:
   - `nextjs-deploy.yml` - For Next.js apps
   - `go-deploy.yml` - For Go services  
   - `static-deploy.yml` - For static sites

## Example Repository Structure

```
your-app/
├── .gitea/
│   └── workflows/
│       └── deploy.yml      # Your deployment workflow
├── Dockerfile              # How to build your app
├── src/                    # Your source code
└── package.json           # For Node.js apps
```

## Testing Your Deployment

1. Add secrets to your repository
2. Copy appropriate workflow to `.gitea/workflows/deploy.yml`
3. Make a commit to `main` branch
4. Watch the Actions tab in Gitea
5. Your app will be deployed to `https://your-repo-name.gmac.io`

## Deployment URLs

- **Production** (main branch): `https://app-name.gmac.io`
- **Staging** (PRs): `https://staging-pr-123.gmac.io`
- **API endpoints**: `https://api.gmac.io`

## Container Registry

Your Docker images are stored at:
- Registry: `ci.gmac.io`
- Image: `ci.gmac.io/mackieg/repo-name:tag`

Pull images manually:
```bash
docker login ci.gmac.io -u mackieg -p 6c0c69be9e3ac745fd234a47e276df22955268ba
docker pull ci.gmac.io/mackieg/your-app:latest
```