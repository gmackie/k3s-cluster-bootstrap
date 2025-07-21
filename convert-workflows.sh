#!/bin/bash
# GitHub Actions to Gitea Actions Conversion Script

echo "=== GitHub Actions to Gitea Actions Converter ==="

if [ ! -d ".github/workflows" ]; then
    echo "No .github/workflows directory found"
    echo "Run this script in the root of your repository after cloning from GitHub"
    exit 1
fi

# Create backup
echo "Creating backup of original workflows..."
mkdir -p .github/workflows-backup
cp -r .github/workflows/* .github/workflows-backup/ 2>/dev/null || true

# Convert workflows
echo "Converting workflows..."
find .github/workflows -name "*.yml" -o -name "*.yaml" | while read file; do
    echo "Processing: $file"
    
    # Create backup of individual file
    cp "$file" "$file.github-backup"
    
    # Common replacements
    sed -i.tmp \
        -e '1i# Converted for Gitea Actions from GitHub Actions' \
        -e 's/secrets\.GITHUB_TOKEN/secrets.GITEA_TOKEN/g' \
        -e 's/\${{ github\.actor }}/\${{ gitea.actor }}/g' \
        "$file"
    
    # Remove temp file
    rm "$file.tmp" 2>/dev/null || true
    
    echo "✓ Converted: $file"
done

# Check for common GitHub-specific actions that need attention
echo ""
echo "=== Manual Review Needed ==="
echo "The following GitHub-specific features were found and may need manual updates:"

grep -r "github-script" .github/workflows/ && echo "→ Replace github-script with direct API calls"
grep -r "create-release" .github/workflows/ && echo "→ Replace with Gitea API release creation"
grep -r "upload-artifact" .github/workflows/ && echo "→ Verify artifact upload works in Gitea"
grep -r "download-artifact" .github/workflows/ && echo "→ Verify artifact download works in Gitea"
grep -r "actions/deploy-pages" .github/workflows/ && echo "→ Replace with custom deployment"

echo ""
echo "=== Conversion Complete ==="
echo "✓ Original workflows backed up to .github/workflows-backup/"
echo "✓ Converted workflows ready for Gitea"
echo ""
echo "Next steps:"
echo "1. Review converted workflows manually"
echo "2. Update any GitHub-specific actions identified above"
echo "3. Add secrets to Gitea repository settings"
echo "4. Test workflows with a small commit"
echo ""
echo "For detailed migration guidance, see: github-to-gitea-migration.md"