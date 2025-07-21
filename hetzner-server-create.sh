#!/bin/bash
# Create new Hetzner server for k3s

echo "=== Creating Hetzner Server for K3s ==="
echo
echo "To create the server, you have two options:"
echo
echo "Option 1: Using Hetzner Cloud Console (Recommended)"
echo "1. Go to: https://console.hetzner.cloud/"
echo "2. Click 'New Server'"
echo "3. Select:"
echo "   - Location: Nuremberg (same as CI server)"
echo "   - Image: Ubuntu 24.04"
echo "   - Type: CPX11 (2 vCPU, 2GB RAM)"
echo "   - Name: k3s-gmac-io"
echo "   - SSH Key: Select your existing key"
echo "4. Create server"
echo
echo "Option 2: Using Hetzner CLI"
echo "If you have hcloud CLI installed:"
echo
echo "hcloud server create \\"
echo "  --name k3s-gmac-io \\"
echo "  --type cpx11 \\"
echo "  --image ubuntu-24.04 \\"
echo "  --location nbg1 \\"
echo "  --ssh-key <your-ssh-key-id>"
echo
echo "After creation, you'll get:"
echo "- Server IP: Use this for DNS records"
echo "- Root access via SSH"
echo
echo "Estimated cost: $4.20/month"