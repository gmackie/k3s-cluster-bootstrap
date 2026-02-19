#!/bin/bash
# Base K3s installation with multi-node support

source "${SCRIPT_DIR}/lib/common.sh"

info "Installing K3s base cluster..."

# Multi-node configuration
MASTER_IP="${MASTER_IP:-}"
NODE_NAME="${NODE_NAME:-$(hostname)}"
NODE_LABELS="${NODE_LABELS:-}"
NODE_TAINTS="${NODE_TAINTS:-}"

# Check if k3s is already installed
if command_exists k3s; then
    warn "K3s is already installed"
    k3s_version=$(k3s --version | head -n1)
    info "Current version: $k3s_version"
    read -p "Do you want to reinstall? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Skipping K3s installation"
        return 0
    fi
fi

# Installation options
K3S_INSTALL_ARGS=""

# Configure based on node type
if [[ "$NODE_TYPE" == "master" ]]; then
    info "Installing K3s master node..."
    
    # Disable traefik if we're using our own ingress
    K3S_INSTALL_ARGS="--disable traefik"
    
    # For multi-node clusters, use external datastore or embedded etcd
    if [[ -n "$MASTER_IP" ]]; then
        # This is an additional master node
        K3S_INSTALL_ARGS="$K3S_INSTALL_ARGS --server https://${MASTER_IP}:6443"
    else
        # This is the first master node
        K3S_INSTALL_ARGS="$K3S_INSTALL_ARGS --cluster-init"
        
        # Configure for multi-master setup
        K3S_INSTALL_ARGS="$K3S_INSTALL_ARGS --node-name $NODE_NAME"
        
        # Add node labels if specified
        if [[ -n "$NODE_LABELS" ]]; then
            K3S_INSTALL_ARGS="$K3S_INSTALL_ARGS --node-label $NODE_LABELS"
        fi
    fi
    
    # Install k3s
    curl -sfL https://get.k3s.io | sh -s - server $K3S_INSTALL_ARGS
    
    # Wait for k3s to be ready
    info "Waiting for K3s to be ready..."
    sleep 10
    kubectl wait --for=condition=Ready node --all --timeout=300s
    
    # Save node token for agent joins
    if [[ "$ENVIRONMENT" == "local" ]]; then
        mkdir -p "${SCRIPT_DIR}/.cluster"
        sudo cat /var/lib/rancher/k3s/server/node-token > "${SCRIPT_DIR}/.cluster/node-token"
        chmod 600 "${SCRIPT_DIR}/.cluster/node-token"
        info "Node token saved to .cluster/node-token"
    fi
    
    # Configure kubectl for non-root user
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    chmod 600 ~/.kube/config
    
    success "K3s master node installed successfully"
    
elif [[ "$NODE_TYPE" == "agent" || "$NODE_TYPE" == "worker" ]]; then
    info "Installing K3s worker node..."
    
    # For agent nodes, we need the master URL and token
    if [[ -z "$MASTER_IP" ]]; then
        if [[ -f "${SCRIPT_DIR}/.cluster/master-ip" ]]; then
            MASTER_IP=$(cat "${SCRIPT_DIR}/.cluster/master-ip")
        else
            read -p "Enter master node IP/hostname: " MASTER_IP
        fi
    fi
    K3S_URL="https://${MASTER_IP}:6443"
    
    if [[ -f "${SCRIPT_DIR}/.cluster/node-token" ]]; then
        K3S_TOKEN=$(cat "${SCRIPT_DIR}/.cluster/node-token")
    else
        read -sp "Enter node token: " K3S_TOKEN
        echo
    fi
    
    # Configure agent with labels and taints
    AGENT_ARGS="--node-name $NODE_NAME"
    
    if [[ -n "$NODE_LABELS" ]]; then
        AGENT_ARGS="$AGENT_ARGS --node-label $NODE_LABELS"
    fi
    
    if [[ -n "$NODE_TAINTS" ]]; then
        AGENT_ARGS="$AGENT_ARGS --node-taint $NODE_TAINTS"
    fi
    
    # Install k3s agent
    curl -sfL https://get.k3s.io | K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -s - agent $AGENT_ARGS
    
    success "K3s worker node installed successfully"
fi

# Install NGINX Ingress Controller (replacing traefik)
if [[ "$NODE_TYPE" == "master" ]]; then
    info "Installing NGINX Ingress Controller..."
    
    # Create ingress-nginx namespace
    ensure_namespace ingress-nginx
    
    # Install NGINX Ingress
    apply_manifest https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
    
    # Wait for ingress controller to be ready
    wait_for_deployment ingress-nginx ingress-nginx-controller
    
    success "NGINX Ingress Controller installed"
fi

# Install cert-manager for automatic SSL
if [[ "$NODE_TYPE" == "master" && -n "$DOMAIN" ]]; then
    info "Installing cert-manager..."
    
    # Install cert-manager
    apply_manifest https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    
    # Wait for cert-manager to be ready
    wait_for_deployment cert-manager cert-manager
    wait_for_deployment cert-manager cert-manager-webhook
    wait_for_deployment cert-manager cert-manager-cainjector
    
    # Create Let's Encrypt ClusterIssuer
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@${DOMAIN}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
    
    success "cert-manager installed with Let's Encrypt"
fi

info "Base K3s installation complete"