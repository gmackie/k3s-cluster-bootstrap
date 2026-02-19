#!/bin/bash
set -euo pipefail

echo "=== Setting up Complete Deployment System ==="

# Create deployment tools directory
DEPLOY_DIR="/opt/gmac-deploy"
sudo mkdir -p $DEPLOY_DIR

# Copy all deployment tools
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo cp $SCRIPT_DIR/deploy-app.sh $DEPLOY_DIR/
sudo cp $SCRIPT_DIR/easy-deploy.sh $DEPLOY_DIR/
sudo cp -r $SCRIPT_DIR/generic-app-chart $DEPLOY_DIR/
sudo cp $SCRIPT_DIR/.github-workflow-template.yml $DEPLOY_DIR/
sudo cp $SCRIPT_DIR/auto-deployment-guide.md $DEPLOY_DIR/
sudo cp -r $SCRIPT_DIR/deployment-ui $DEPLOY_DIR/

# Make scripts executable
sudo chmod +x $DEPLOY_DIR/*.sh

# Create symlink for easy access
sudo ln -sf $DEPLOY_DIR/easy-deploy.sh /usr/local/bin/deploy-app

# Apply ArgoCD ApplicationSet
KUBECONFIG=/Users/mackieg/.kube/config-hetzner kubectl apply -f $SCRIPT_DIR/auto-deploy-appset.yaml

# Push generic chart to Gitea
cd /tmp
if [ ! -d "charts" ]; then
    git clone https://git.gmac.io/gmackie/charts.git || {
        # If charts repo doesn't exist, create it
        echo "Creating charts repository..."
        ssh root@ci.gmac.io "su git -c 'cd /var/lib/gitea/repositories/gmackie && git init --bare charts.git'"
        git clone https://git.gmac.io/gmackie/charts.git
    }
fi

cd charts
mkdir -p generic-app
cp -r $SCRIPT_DIR/generic-app-chart/* generic-app/
git add .
git commit -m "Add generic app Helm chart" || true
git push || echo "Push failed - you may need to push manually"

echo ""
echo "=== Deployment System Setup Complete ==="
echo ""
echo "Usage:"
echo "  deploy-app                    # Interactive mode"
echo "  deploy-app <repo-name>        # Deploy with default domain"
echo "  deploy-app <repo> <domain>    # Deploy with custom domain"
echo ""
echo "All tools installed in: $DEPLOY_DIR"
echo "Documentation: $DEPLOY_DIR/auto-deployment-guide.md"