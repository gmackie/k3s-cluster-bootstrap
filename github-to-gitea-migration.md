# GitHub Actions to Gitea Actions Migration Guide

## Overview
Gitea Actions is largely compatible with GitHub Actions, but there are some key differences and considerations when migrating workflows.

## What Works Without Changes

### ✅ Fully Compatible
- **YAML syntax**: Same workflow structure
- **Trigger events**: `push`, `pull_request`, `schedule`, etc.
- **Job structure**: `jobs`, `steps`, `runs-on`
- **Environment variables**: `env`, `secrets`
- **Matrix builds**: `strategy.matrix`
- **Conditional execution**: `if` statements
- **Action marketplace**: Most actions work

### ✅ Common Actions That Work
```yaml
# These actions work as-is in Gitea
- uses: actions/checkout@v4
- uses: actions/setup-node@v4
- uses: actions/setup-go@v4
- uses: actions/setup-python@v4
- uses: actions/cache@v3
- uses: docker/build-push-action@v5
```

## Required Changes

### 1. Runner Labels
**GitHub Actions:**
```yaml
runs-on: ubuntu-latest
```

**Gitea Actions:**
```yaml
runs-on: ubuntu-latest  # Works if you have ubuntu runners
# OR use your custom labels
runs-on: self-hosted
```

### 2. GitHub-Specific Actions
Some GitHub-specific actions need alternatives:

**GitHub Actions:**
```yaml
- uses: actions/github-script@v7
- uses: actions/create-release@v1
```

**Gitea Actions:**
```yaml
# Use Gitea API directly
- name: Create Release
  run: |
    curl -X POST "https://ci.gmac.io/api/v1/repos/${{ github.repository }}/releases" \
      -H "Authorization: token ${{ secrets.GITEA_TOKEN }}" \
      -H "Content-Type: application/json" \
      -d '{"tag_name": "${{ github.ref_name }}", "name": "Release ${{ github.ref_name }}"}'
```

### 3. Context Variables
Most GitHub context variables work, but some are different:

**GitHub Actions:**
```yaml
${{ github.repository }}
${{ github.sha }}
${{ github.ref }}
```

**Gitea Actions:**
```yaml
${{ github.repository }}  # Still works
${{ github.sha }}         # Still works
${{ github.ref }}         # Still works
# Additional Gitea-specific contexts available
${{ gitea.repository }}
```

## Migration Steps

### Step 1: Backup Original Workflows
```bash
# Before importing, backup your workflows
mkdir -p workflow-backups
cp -r .github/workflows/* workflow-backups/
```

### Step 2: Update Runner Configuration
1. **Check available runners in Gitea:**
   - Go to Settings → Actions → Runners
   - Note the available labels

2. **Update `runs-on` values:**
```yaml
# If you have multiple runner types
runs-on: ubuntu-22.04    # Specific version
runs-on: self-hosted     # Generic self-hosted
runs-on: [self-hosted, linux, x64]  # Multiple labels
```

### Step 3: Update Secrets
1. **In GitHub:** Go to Settings → Secrets and Variables
2. **In Gitea:** Go to Settings → Secrets
3. **Copy all secrets** to Gitea with the same names

### Step 4: Test and Validate
Create a simple test workflow first:

```yaml
name: Test Gitea Actions
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Test Basic Commands
        run: |
          echo "Repository: ${{ github.repository }}"
          echo "Branch: ${{ github.ref }}"
          echo "SHA: ${{ github.sha }}"
          pwd
          ls -la
```

## Common Migration Patterns

### Next.js/Vercel Migration
**Before (GitHub + Vercel):**
```yaml
name: Deploy to Vercel
on: [push]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '18'
      - run: npm ci
      - run: npm run build
      - uses: amondnet/vercel-action@v25
```

**After (Gitea + Self-hosted):**
```yaml
name: Deploy Next.js
on: [push]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '18'
      - run: npm ci
      - run: npm run build
      - name: Deploy to Server
        run: |
          rsync -avz --delete ./out/ user@your-server:/var/www/your-app/
        env:
          SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
```

### Docker Build Migration
**Before and After (mostly identical):**
```yaml
name: Build Docker Image
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}  # Change to GITEA_TOKEN
      - uses: docker/build-push-action@v5
        with:
          push: true
          tags: ghcr.io/${{ github.repository }}:latest
```

## Troubleshooting Common Issues

### Issue 1: Runner Not Found
**Error:** `No runner available for label 'ubuntu-latest'`
**Solution:** 
- Check available runners in Gitea Settings → Actions
- Update `runs-on` to match available labels
- Register additional runners if needed

### Issue 2: Action Not Found
**Error:** `Action 'some-action' not found`
**Solution:**
- Check if action is available in the GitHub marketplace
- Use alternative actions or implement with `run` commands
- Use `docker://` prefix for Docker actions

### Issue 3: Secrets Not Working
**Error:** Secret values are empty
**Solution:**
- Verify secrets are added in Gitea repository settings
- Check secret names match exactly (case-sensitive)
- Ensure repository has access to organization secrets

## Migration Checklist

### Pre-Migration
- [ ] Document current workflows and their purposes
- [ ] List all secrets and environment variables
- [ ] Identify custom actions and GitHub-specific features
- [ ] Set up Gitea runners with appropriate labels

### During Migration
- [ ] Import repositories using bulk import script
- [ ] Copy secrets from GitHub to Gitea
- [ ] Update `runs-on` labels in workflows
- [ ] Replace GitHub-specific actions
- [ ] Test workflows with small changes first

### Post-Migration
- [ ] Verify all workflows trigger correctly
- [ ] Test deployment processes end-to-end
- [ ] Monitor resource usage on Gitea server
- [ ] Set up backup procedures for Gitea
- [ ] Update team documentation and processes

## Workflow Conversion Script

For bulk conversion, you can use this script:

```bash
#!/bin/bash
# Convert GitHub Actions workflows for Gitea
find .github/workflows -name "*.yml" -o -name "*.yaml" | while read file; do
    echo "Converting $file"
    # Replace GitHub-specific runner labels
    sed -i.bak 's/runs-on: ubuntu-latest/runs-on: ubuntu-latest/g' "$file"
    # Add Gitea-specific comments
    sed -i.bak '1i# Converted for Gitea Actions' "$file"
    echo "Converted: $file"
done
```

## Need Help?

1. **Test workflows incrementally** - Don't migrate everything at once
2. **Use the Gitea Actions documentation** - Available in your Gitea instance
3. **Check runner logs** - Available in the Actions tab of your repository
4. **Monitor server resources** - Ensure your VPS can handle the workload

Most workflows will work with minimal changes. The biggest considerations are runner availability and replacing GitHub-specific integrations.