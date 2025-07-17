#!/bin/bash

# Storage Management for Gitea

# Check current disk usage
echo "=== Current Disk Usage ==="
df -h

# Estimate Gitea storage needs
echo -e "\n=== Typical Storage Requirements ==="
echo "- Code repos: ~100MB-1GB each"
echo "- CI artifacts: ~500MB-2GB per project"
echo "- Docker images: ~1-5GB each"
echo "- Database: ~100MB-1GB"

# Monitor disk usage
cat > /usr/local/bin/check-gitea-storage.sh << 'EOF'
#!/bin/bash
THRESHOLD=80
USAGE=$(df / | grep / | awk '{ print $5 }' | sed 's/%//g')

if [ $USAGE -gt $THRESHOLD ]; then
    echo "WARNING: Disk usage is at ${USAGE}%"
    # Send alert (email, Discord, etc)
fi

# Check Gitea specific directories
echo "=== Gitea Storage Breakdown ==="
du -sh /var/lib/gitea/data/* 2>/dev/null | sort -rh | head -10
du -sh /var/lib/docker/* 2>/dev/null | sort -rh | head -5
EOF

chmod +x /usr/local/bin/check-gitea-storage.sh

# Add to crontab
echo "0 */6 * * * /usr/local/bin/check-gitea-storage.sh" | crontab -

# Cleanup old Docker images weekly
cat > /usr/local/bin/docker-cleanup.sh << 'EOF'
#!/bin/bash
# Remove unused Docker images
docker image prune -af --filter "until=168h"
# Remove stopped containers
docker container prune -f
# Clean build cache
docker builder prune -af --filter "until=168h"
EOF

chmod +x /usr/local/bin/docker-cleanup.sh
echo "0 2 * * 0 /usr/local/bin/docker-cleanup.sh" | crontab -

echo "Storage monitoring configured!"