# Quick Migration Reference

## TL;DR - Most Important Changes

### 1. Secrets
```yaml
# Change this:
password: ${{ secrets.GITHUB_TOKEN }}

# To this:
password: ${{ secrets.GITEA_TOKEN }}
```

### 2. Common GitHub-Specific Actions
```yaml
# Replace these with Gitea API calls:
- uses: actions/github-script@v7        # Use curl + Gitea API
- uses: actions/create-release@v1       # Use curl + Gitea API  
- uses: actions/upload-release-asset@v1 # Use curl + Gitea API
```

### 3. Everything Else Usually Works
```yaml
# These work as-is:
- uses: actions/checkout@v4
- uses: actions/setup-node@v4
- uses: actions/setup-go@v4
- uses: actions/cache@v3
- uses: docker/build-push-action@v5
runs-on: ubuntu-latest
strategy:
  matrix: [...]
```

## Quick Migration Process

1. **Import repos with bulk script:**
   ```bash
   python gitea-bulk-import.py
   ```

2. **Convert workflows:**
   ```bash
   ./convert-workflows.sh
   ```

3. **Add secrets in Gitea:**
   - Go to repo Settings → Secrets
   - Copy all secrets from GitHub

4. **Test with small commit**

## Runner Labels Available
- `ubuntu-latest` (if configured)
- `self-hosted`
- `linux`, `x64` (depends on your setup)

Check your available runners: Gitea → Settings → Actions → Runners

## Most Workflows Need Zero Changes
The bulk import preserves workflows, and 80%+ work immediately after adding secrets.