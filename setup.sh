#!/bin/bash

# Setup script for gmac-io-ci project

echo "=== Setting up gmac-io-ci project ==="

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate venv and install dependencies
echo "Installing dependencies..."
source venv/bin/activate
pip install -r requirements.txt

# Initialize git if needed
if [ ! -d ".git" ]; then
    echo "Initializing git repository..."
    git init
fi

# Add all files and create initial commit
echo "Creating initial commit..."
git add .
git commit -m "Initial CI/CD setup with Gitea

- Gitea deployment configuration
- Docker compose setup  
- GitHub bulk import script
- Example workflows for Next.js, Go, and Rust
- Server setup scripts for Hetzner
- Documentation and architecture notes"

echo ""
echo "Setup complete! To use the bulk import script:"
echo "1. source venv/bin/activate"
echo "2. python gitea-bulk-import.py"
echo ""
echo "To push to your Gitea instance:"
echo "git remote add origin https://ci.gmac.io/yourusername/gmac-io-ci.git"
echo "git push -u origin main"