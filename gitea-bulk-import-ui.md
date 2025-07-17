# Gitea Bulk Import Guide

## Method 1: Using Gitea Web UI (Easiest)

1. **Get your GitHub Personal Access Token**
   - Go to GitHub → Settings → Developer settings → Personal access tokens
   - Generate token with `repo` scope

2. **In Gitea Web UI**
   - Click "+" → "New Migration"
   - Choose "GitHub" as source
   - Enter your GitHub token
   - Check "Migrate all repositories"
   - Select what to import (issues, PRs, wiki, etc.)
   - Click "Migrate"

## Method 2: Using Gitea API (More Control)

1. **Get Gitea API Token**
   ```bash
   # In Gitea: Settings → Applications → Generate New Token
   # Scopes needed: repo
   ```

2. **Quick import script**
   ```bash
   # Import specific repos
   GITEA_TOKEN="your-token-here"
   
   import_repo() {
     curl -X POST "https://ci.gmac.io/api/v1/repos/migrate" \
       -H "Authorization: token $GITEA_TOKEN" \
       -H "Content-Type: application/json" \
       -d "{
         \"clone_addr\": \"https://github.com/yourusername/$1.git\",
         \"repo_name\": \"$1\",
         \"mirror\": false,
         \"private\": false
       }"
   }
   
   # Import multiple repos
   import_repo "repo1"
   import_repo "repo2"
   import_repo "repo3"
   ```

## Method 3: Using GitHub CLI + Script

```bash
# List all your repos and import
gh repo list --limit 1000 | while read -r repo _; do
  repo_name=$(echo $repo | cut -d'/' -f2)
  echo "Importing $repo_name..."
  
  curl -X POST "https://ci.gmac.io/api/v1/repos/migrate" \
    -H "Authorization: token $GITEA_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"clone_addr\": \"https://github.com/$repo.git\",
      \"repo_name\": \"$repo_name\"
    }"
  
  sleep 1
done
```

## Organization Import

To import an entire GitHub organization:

```bash
# Import all repos from an org
ORG_NAME="your-org"

gh repo list $ORG_NAME --limit 1000 --json name,isPrivate | \
jq -r '.[] | [.name, .isPrivate] | @tsv' | \
while IFS=$'\t' read -r name private; do
  curl -X POST "https://ci.gmac.io/api/v1/repos/migrate" \
    -H "Authorization: token $GITEA_TOKEN" \
    -d "{
      \"clone_addr\": \"https://github.com/$ORG_NAME/$name.git\",
      \"repo_name\": \"$name\",
      \"private\": $private
    }"
done
```

## Tips

1. **For private repos**: Add GitHub token to clone URL:
   ```
   https://YOUR_GITHUB_TOKEN@github.com/user/repo.git
   ```

2. **Create organizations first** in Gitea if you want to organize repos

3. **Use mirror mode** if you want to keep repos synced automatically

4. **Batch import**: The web UI method can import all repos at once!