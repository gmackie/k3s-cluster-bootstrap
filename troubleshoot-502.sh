#!/bin/bash

# Troubleshoot 502 Bad Gateway

echo "=== Debugging 502 Error ==="

# 1. Check if Gitea is running
echo "1. Checking Docker containers:"
docker ps -a

# 2. Check Gitea logs
echo -e "\n2. Gitea logs:"
docker logs gitea --tail 20

# 3. Check if Gitea is listening
echo -e "\n3. Checking ports:"
netstat -tlnp | grep 3000

# 4. Test direct connection
echo -e "\n4. Testing direct connection:"
curl -I http://localhost:3000

# 5. Check Nginx error log
echo -e "\n5. Nginx errors:"
tail -20 /var/log/nginx/error.log

# Common fixes:
echo -e "\n=== Common Fixes ==="

# Fix 1: Restart containers
echo "Fix 1 - Restart containers:"
echo "cd /opt/gitea && docker-compose restart"

# Fix 2: Check if Gitea needs more time to start
echo -e "\nFix 2 - Wait for Gitea to fully start:"
echo "docker logs -f gitea  # Watch until you see 'Listen: http://0.0.0.0:3000'"

# Fix 3: Check Docker networking
echo -e "\nFix 3 - Verify Docker network:"
docker network ls
docker inspect gitea | grep -A 10 NetworkMode

# Fix 4: Firewall check
echo -e "\nFix 4 - Check firewall:"
ufw status

# Quick fix script
cat > /tmp/fix-502.sh << 'FIXSCRIPT'
#!/bin/bash
cd /opt/gitea

# Restart everything
docker-compose down
docker-compose up -d

# Wait for Gitea to start
echo "Waiting for Gitea to start..."
sleep 30

# Test connection
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    echo "✓ Gitea is running!"
    systemctl reload nginx
    echo "Try https://ci.gmac.io now"
else
    echo "✗ Gitea still not responding"
    docker logs gitea --tail 50
fi
FIXSCRIPT

chmod +x /tmp/fix-502.sh
echo -e "\nRun: /tmp/fix-502.sh to attempt auto-fix"