# GitHub to Gitea Migration Guide

## Option 1: Full Migration (Recommended)
Move completely to Gitea as your primary Git host.

### Steps:
1. **Mirror all repos from GitHub to Gitea**
   - In Gitea: New Repository → Migration → Clone from GitHub
   - Keeps full history, issues, PRs

2. **Update local remotes**
   ```bash
   git remote set-url origin https://ci.gmac.io/yourorg/yourrepo.git
   git remote add github https://github.com/yourorg/yourrepo.git  # Keep as backup
   ```

3. **Update team workflows**
   - Point CI/CD to Gitea
   - Update documentation
   - Migrate secrets/variables

## Option 2: Hybrid Approach
Keep GitHub as primary, use Gitea for CI/CD only.

### Setup:
1. **Configure auto-mirroring**
   - Gitea pulls from GitHub automatically
   - Set up webhooks for instant sync

2. **GitHub webhook to trigger Gitea CI**
   ```bash
   # In GitHub repo settings → Webhooks
   URL: https://ci.gmac.io/api/v1/repos/yourorg/yourrepo/mirror-sync
   Secret: your-webhook-secret
   ```

## Option 3: Gradual Migration
Start with less critical repos, migrate over time.

### Benefits of Full Migration:
- Complete control over your code
- No GitHub API rate limits
- Faster CI/CD (local Git operations)
- Lower costs (no GitHub paid features)
- Full data sovereignty

### Keep GitHub for:
- Public open source projects
- Community collaboration
- Existing integrations