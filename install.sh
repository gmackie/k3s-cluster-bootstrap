#!/bin/bash
# K3s Cluster Bootstrap Installer
# One-line installation script

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        K3s Cluster Bootstrap System Installer        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git is not installed${NC}"
    echo "Please install git first:"
    echo "  Ubuntu/Debian: sudo apt-get install git"
    echo "  RHEL/CentOS: sudo yum install git"
    echo "  macOS: brew install git"
    exit 1
fi

# Default installation directory
INSTALL_DIR="${INSTALL_DIR:-$HOME/k3s-cluster}"

echo -e "${BLUE}Installation directory:${NC} $INSTALL_DIR"
echo

# Clone repository
if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "${BLUE}Directory exists. Updating...${NC}"
    cd "$INSTALL_DIR"
    git pull
else
    echo -e "${BLUE}Cloning repository...${NC}"
    git clone https://github.com/yourusername/gmac-io-ci.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# Make scripts executable
echo -e "${BLUE}Setting up permissions...${NC}"
chmod +x setup-wizard.sh bootstrap.sh
find scripts -name "*.sh" -exec chmod +x {} \;
find components -name "*.sh" -exec chmod +x {} \;

echo
echo -e "${GREEN}✅ Installation complete!${NC}"
echo
echo -e "${BLUE}Next steps:${NC}"
echo "1. cd $INSTALL_DIR"
echo "2. ./setup-wizard.sh"
echo
echo -e "${BLUE}The setup wizard will guide you through:${NC}"
echo "  • Domain configuration"
echo "  • GitHub OAuth setup"
echo "  • Component selection"
echo "  • Cluster deployment"
echo
echo -e "${GREEN}Happy clustering! 🚀${NC}"