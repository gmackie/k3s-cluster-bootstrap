#!/bin/bash

# Quick bulk import script using GitHub CLI

echo "=== Gitea Bulk Import from GitHub ==="

# Get Gitea token
echo "1. Get your Gitea API token:"
echo "   Visit: https://ci.gmac.io/user/settings/applications"
echo "   Create token with 'repo' scope"
echo ""
read -p "Enter your Gitea API token: " GITEA_TOKEN

# Get GitHub info
read -p "Enter your GitHub username: " GITHUB_USER
read -p "Import private repos? (y/n): " IMPORT_PRIVATE

# Function to import repo
import_repo() {
    local repo_full_name=$1
    local repo_name=$(echo $repo_full_name | cut -d'/' -f2)
    local is_private=$2
    
    echo -n "Importing $repo_name... "
    
    response=$(curl -s -w "\n%{http_code}" -X POST "https://ci.gmac.io/api/v1/repos/migrate" \
        -H "Authorization: token $GITEA_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"clone_addr\": \"https://github.com/${repo_full_name}.git\",
            \"repo_name\": \"${repo_name}\",
            \"private\": ${is_private},
            \"wiki\": true,
            \"issues\": true,
            \"pull_requests\": true,
            \"releases\": true
        }")
    
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "201" ]; then
        echo "✓"
    elif [ "$http_code" = "409" ]; then
        echo "already exists"
    else
        echo "failed ($http_code)"
    fi
    
    sleep 1
}

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "Installing GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update && sudo apt install gh -y
fi

# Get repo list
echo ""
echo "Fetching your GitHub repositories..."

if [ "$IMPORT_PRIVATE" = "y" ]; then
    repos=$(gh repo list $GITHUB_USER --limit 1000 --json nameWithOwner,isPrivate | jq -r '.[] | "\(.nameWithOwner):\(.isPrivate)"')
else
    repos=$(gh repo list $GITHUB_USER --limit 1000 --json nameWithOwner,isPrivate | jq -r '.[] | select(.isPrivate == false) | "\(.nameWithOwner):\(.isPrivate)"')
fi

repo_count=$(echo "$repos" | wc -l)
echo "Found $repo_count repositories to import"
echo ""

# Import each repo
counter=0
echo "$repos" | while IFS=: read -r repo_name is_private; do
    counter=$((counter + 1))
    echo -n "[$counter/$repo_count] "
    import_repo "$repo_name" "$is_private"
done

echo ""
echo "Import complete! Visit https://ci.gmac.io to see your repositories."