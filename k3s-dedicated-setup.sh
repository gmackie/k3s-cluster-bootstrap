#!/bin/bash
# K3s Installation Script for dedicated k3s server
# No conflicts with Gitea since this is a separate server

set -e

echo "=== K3s Installation for Dedicated Server ==="
echo "This script installs k3s on a dedicated server"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Install k3s with standard options (no resource limits needed on dedicated server)
echo "Installing k3s..."
curl -sfL https://get.k3s.io | sh -s - \
    --write-kubeconfig-mode 644 \
    --disable traefik

# Wait for k3s to be ready
echo "Waiting for k3s to start..."
sleep 30
kubectl wait --for=condition=Ready nodes --all --timeout=60s

# Install Nginx Ingress Controller
echo "Installing Nginx Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml

# Install cert-manager for automatic HTTPS
echo "Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
sleep 30
kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=60s

# Create ClusterIssuer for Let's Encrypt
echo "Configuring Let's Encrypt..."
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@gmac.io
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# Create namespaces
echo "Creating namespaces..."
kubectl create namespace production || true
kubectl create namespace staging || true

# Create docker registry secret for Gitea
echo "Setting up Gitea registry access..."
GITEA_USER="mackieg"
GITEA_TOKEN="6c0c69be9e3ac745fd234a47e276df22955268ba"

for ns in default production staging; do
    kubectl create secret docker-registry gitea-registry \
        --docker-server=ci.gmac.io \
        --docker-username=$GITEA_USER \
        --docker-password=$GITEA_TOKEN \
        --namespace=$ns || true
done

# Install metrics server for resource monitoring
echo "Installing metrics server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Save kubeconfig for remote access
echo "Saving kubeconfig..."
SERVER_IP=$(curl -s https://ipinfo.io/ip)
cat /etc/rancher/k3s/k3s.yaml | sed "s/127.0.0.1/$SERVER_IP/" > /root/k3s-kubeconfig.yaml

echo
echo "=== K3s Installation Complete ==="
echo
echo "Server IP: $SERVER_IP"
echo
echo "Next steps:"
echo "1. Update DNS records:"
echo "   *.gmac.io → $SERVER_IP"
echo "   api.gmac.io → $SERVER_IP"
echo "   app.gmac.io → $SERVER_IP"
echo "   staging-*.gmac.io → $SERVER_IP"
echo
echo "2. Copy kubeconfig to your local machine:"
echo "   scp root@$SERVER_IP:/root/k3s-kubeconfig.yaml ~/.kube/k3s-gmac.yaml"
echo "   export KUBECONFIG=~/.kube/k3s-gmac.yaml"
echo
echo "3. Verify installation:"
echo "   kubectl get nodes"
echo "   kubectl get pods -A"
echo
echo "Kubernetes API: https://$SERVER_IP:6443"