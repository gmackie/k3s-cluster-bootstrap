#!/bin/bash
# Cleanup k3s from CI server (since we need a dedicated server)

echo "=== Removing k3s from CI server ==="
echo "This will free up resources for CI/CD tasks"

# Uninstall k3s
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    echo "Uninstalling k3s..."
    /usr/local/bin/k3s-uninstall.sh
    echo "✓ k3s removed"
else
    echo "k3s uninstall script not found, may already be removed"
fi

# Clean up any remaining k3s data
rm -rf /etc/rancher/k3s
rm -rf /var/lib/rancher/k3s
rm -f /root/k3s-kubeconfig.yaml

echo
echo "=== Cleanup Complete ==="
echo "The CI server is now dedicated to Gitea only"
echo "Please create a new server for k3s deployment"