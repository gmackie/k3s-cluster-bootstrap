#!/bin/bash
set -euo pipefail

# Make the script more robust and user-friendly
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ASCII Art Banner
cat << "EOF"
╔═══════════════════════════════════════╗
║        Easy App Deployer              ║
║   Deploy to Kubernetes in seconds!    ║
╚═══════════════════════════════════════╝
EOF

echo ""

# Interactive mode if no args provided
if [ $# -eq 0 ]; then
    echo -e "${BLUE}Welcome to Easy Deploy!${NC}"
    echo ""
    
    # List available repositories
    echo -e "${YELLOW}Fetching your repositories...${NC}"
    REPOS=$(ssh root@ci.gmac.io "ls -1 /var/lib/gitea/repositories/gmackie/ | sed 's/\.git$//' | sort" 2>/dev/null || echo "")
    
    if [ -z "$REPOS" ]; then
        echo -e "${RED}Could not fetch repositories. Please check your connection.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Available repositories:${NC}"
    echo "$REPOS" | nl -v 1
    echo ""
    
    read -p "Select repository number (or type name): " REPO_CHOICE
    
    # Check if numeric choice
    if [[ "$REPO_CHOICE" =~ ^[0-9]+$ ]]; then
        REPO_NAME=$(echo "$REPOS" | sed -n "${REPO_CHOICE}p")
    else
        REPO_NAME="$REPO_CHOICE"
    fi
    
    # Validate repo exists
    if ! echo "$REPOS" | grep -q "^${REPO_NAME}$"; then
        echo -e "${RED}Repository '$REPO_NAME' not found!${NC}"
        exit 1
    fi
    
    # Domain selection
    echo ""
    DEFAULT_DOMAIN="${REPO_NAME}.gmac.io"
    read -p "Enter domain [${DEFAULT_DOMAIN}]: " DOMAIN
    DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}
    
    # Port selection
    echo ""
    read -p "Enter application port [3000]: " PORT
    PORT=${PORT:-3000}
    
    # Confirmation
    echo ""
    echo -e "${BLUE}=== Deployment Summary ===${NC}"
    echo "Repository: $REPO_NAME"
    echo "Domain: $DOMAIN"
    echo "Port: $PORT"
    echo ""
    read -p "Deploy now? (y/N): " CONFIRM
    
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
else
    # Use command line args
    REPO_NAME=$1
    DOMAIN=${2:-"${REPO_NAME}.gmac.io"}
    PORT=${3:-"3000"}
fi

# Run the deployment
echo ""
echo -e "${YELLOW}🚀 Starting deployment...${NC}"
echo ""

# Use the deploy script
if [ -f "$SCRIPT_DIR/deploy-app.sh" ]; then
    bash "$SCRIPT_DIR/deploy-app.sh" "$REPO_NAME" "$DOMAIN" "$PORT"
else
    echo -e "${RED}Error: deploy-app.sh not found!${NC}"
    exit 1
fi

# Post-deployment info
echo ""
echo -e "${GREEN}✅ Deployment setup complete!${NC}"
echo ""
echo -e "${BLUE}What happens next:${NC}"
echo "1. Push any change to the repository to trigger deployment"
echo "2. First deployment may take 2-5 minutes"
echo "3. SSL certificate will be automatically provisioned"
echo ""
echo -e "${BLUE}Useful links:${NC}"
echo "📦 Repository: https://git.gmac.io/gmackie/$REPO_NAME"
echo "🌐 Application: https://$DOMAIN (available after deployment)"
echo "📊 ArgoCD: https://argocd.gmac.io/applications/$REPO_NAME"
echo "🐳 Harbor: https://registry.gmac.io/harbor/projects/apps/repositories"
echo ""
echo -e "${YELLOW}Quick test deployment:${NC}"
echo "cd /path/to/$REPO_NAME"
echo "echo '# Deployment $(date)' >> README.md"
echo "git add . && git commit -m 'Initial deployment' && git push"
echo ""