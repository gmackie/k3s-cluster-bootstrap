#!/bin/bash

# Bulk import GitHub repos to Gitea

# Configuration
GITEA_URL="https://ci.gmac.io"
GITEA_USER="your-gitea-username"
GITEA_TOKEN="your-gitea-api-token"  # Get from Settings -> Applications -> Generate Token
GITHUB_USER="your-github-username"
GITHUB_TOKEN="your-github-token"    # Optional, for private repos

# Function to migrate a single repo
migrate_repo() {
    local repo_name=$1
    local is_private=$2
    local github_url="https://github.com/${GITHUB_USER}/${repo_name}.git"
    
    echo "Migrating ${repo_name}..."
    
    curl -X POST "${GITEA_URL}/api/v1/repos/migrate" \
        -H "Authorization: token ${GITEA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"clone_addr\": \"${github_url}\",
            \"uid\": 1,
            \"repo_name\": \"${repo_name}\",
            \"mirror\": false,
            \"private\": ${is_private},
            \"description\": \"Migrated from GitHub\",
            \"wiki\": true,
            \"issues\": true,
            \"pull_requests\": true,
            \"releases\": true,
            \"milestones\": true,
            \"labels\": true
        }"
    
    echo "✓ ${repo_name} migrated"
    sleep 2  # Be nice to the API
}

# Method 1: List specific repos
echo "=== Method 1: Import specific repos ==="
cat > repos-to-import.txt << 'EOF'
# Add your repo names here, one per line
# Format: repo-name:private (true/false)
my-web-app:false
backend-api:true
documentation:false
EOF

# Import from list
while IFS=: read -r repo private; do
    [[ "$repo" =~ ^#.*$ ]] && continue
    [[ -z "$repo" ]] && continue
    migrate_repo "$repo" "${private:-false}"
done < repos-to-import.txt

# Method 2: Import ALL repos from GitHub
echo -e "\n=== Method 2: Import ALL repos automatically ==="
cat > import-all-github-repos.sh << 'IMPORT_ALL'
#!/bin/bash

# Get all repos from GitHub
gh repo list ${GITHUB_USER} --limit 1000 --json name,isPrivate,description | \
jq -r '.[] | "\(.name):\(.isPrivate):\(.description)"' | \
while IFS=: read -r name private desc; do
    private_bool=$([ "$private" = "true" ] && echo "true" || echo "false")
    
    # Create in Gitea
    curl -X POST "${GITEA_URL}/api/v1/repos/migrate" \
        -H "Authorization: token ${GITEA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"clone_addr\": \"https://github.com/${GITHUB_USER}/${name}.git\",
            \"uid\": 1,
            \"repo_name\": \"${name}\",
            \"mirror\": false,
            \"private\": ${private_bool},
            \"description\": \"${desc}\"
        }"
    
    echo "✓ Imported ${name}"
    sleep 1
done
IMPORT_ALL

# Method 3: Keep repos synced (mirror mode)
echo -e "\n=== Method 3: Setup auto-sync mirrors ==="
cat > setup-mirror.sh << 'MIRROR'
#!/bin/bash

# This keeps repos automatically synced from GitHub
setup_mirror() {
    local repo_name=$1
    
    curl -X POST "${GITEA_URL}/api/v1/repos/migrate" \
        -H "Authorization: token ${GITEA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"clone_addr\": \"https://github.com/${GITHUB_USER}/${repo_name}.git\",
            \"uid\": 1,
            \"repo_name\": \"${repo_name}\",
            \"mirror\": true,
            \"mirror_interval\": \"10m\",
            \"private\": false
        }"
}

# Setup mirrors for specific repos
setup_mirror "my-important-repo"
setup_mirror "another-repo"
MIRROR

echo "Edit the configuration variables and run!"