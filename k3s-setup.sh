#!/bin/bash
# K3s Installation Script for ci.gmac.io
# Installs k3s with resource constraints suitable for shared CI/CD server

set -e

echo "=== K3s Installation for GMAC.io ==="
echo "This script will install k3s on the CI server with resource limits"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use: ssh root@5.78.92.8)"
    exit 1
fi

# Install k3s with specific options
echo "Installing k3s..."
curl -sfL https://get.k3s.io | sh -s - \
    --write-kubeconfig-mode 644 \
    --disable traefik \
    --kubelet-arg="max-pods=50" \
    --kubelet-arg="eviction-hard=memory.available<200Mi" \
    --kubelet-arg="eviction-soft=memory.available<300Mi" \
    --kubelet-arg="eviction-soft-grace-period=memory.available=2m"

# Wait for k3s to be ready
echo "Waiting for k3s to start..."
sleep 30
kubectl wait --for=condition=Ready nodes --all --timeout=60s

# Install Nginx Ingress Controller (lighter than Traefik)
echo "Installing Nginx Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml

# Create resource quota for default namespace
echo "Setting up resource quotas..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: default-quota
  namespace: default
spec:
  hard:
    requests.cpu: "1"
    requests.memory: "800Mi"
    limits.cpu: "1.5"
    limits.memory: "1Gi"
    persistentvolumeclaims: "5"
EOF

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

# Apply resource quotas to namespaces
for ns in production staging; do
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${ns}-quota
  namespace: ${ns}
spec:
  hard:
    requests.cpu: "500m"
    requests.memory: "400Mi"
    limits.cpu: "1"
    limits.memory: "600Mi"
EOF
done

# Create docker registry secret for Gitea
echo "Setting up Gitea registry access..."
GITEA_USER="mackieg"
GITEA_TOKEN="6c0c69be9e3ac745fd234a47e276df22955268ba"
kubectl create secret docker-registry gitea-registry \
    --docker-server=ci.gmac.io \
    --docker-username=$GITEA_USER \
    --docker-password=$GITEA_TOKEN \
    --namespace=default || true

# Copy secret to other namespaces
for ns in production staging; do
    kubectl get secret gitea-registry -o yaml | \
    sed "s/namespace: default/namespace: $ns/" | \
    kubectl apply -f -
done

# Save kubeconfig for remote access
echo "Saving kubeconfig..."
cat /etc/rancher/k3s/k3s.yaml | sed "s/127.0.0.1/5.78.92.8/" > /root/k3s-kubeconfig.yaml

echo
echo "=== K3s Installation Complete ==="
echo
echo "Next steps:"
echo "1. Copy kubeconfig to your local machine:"
echo "   scp root@5.78.92.8:/root/k3s-kubeconfig.yaml ~/.kube/gmac-k3s.yaml"
echo "   export KUBECONFIG=~/.kube/gmac-k3s.yaml"
echo
echo "2. Update DNS records:"
echo "   *.k3s.gmac.io → 5.78.92.8"
echo "   staging-*.gmac.io → 5.78.92.8"
echo
echo "3. Update Gitea token in the script and re-run the registry secret creation"
echo
echo "Kubernetes API is available at: https://5.78.92.8:6443"