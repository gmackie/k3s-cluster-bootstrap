#!/bin/bash
# Hetzner Cloud environment setup

source "${SCRIPT_DIR}/lib/common.sh"

info "Setting up Hetzner Cloud environment..."

# Check for hcloud CLI
if ! command_exists hcloud; then
    info "Installing Hetzner Cloud CLI..."
    
    # Detect OS and install accordingly
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install hcloud
    elif [[ -f /etc/debian_version ]]; then
        wget -O hcloud.tar.gz https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz
        tar -xzf hcloud.tar.gz
        sudo mv hcloud /usr/local/bin/
        rm hcloud.tar.gz
    else
        error "Unsupported OS for automatic hcloud installation"
    fi
fi

# Configure hcloud context
hcloud context create k3s-cluster || true
hcloud context use k3s-cluster

# Set the API token
export HCLOUD_TOKEN="$HETZNER_API_TOKEN"

# Configuration
SERVER_TYPE="${HETZNER_SERVER_TYPE:-cpx11}"
LOCATION="${HETZNER_LOCATION:-nbg1}"
IMAGE="${HETZNER_IMAGE:-ubuntu-22.04}"
SSH_KEY_NAME="k3s-cluster-key"

# Create SSH key if it doesn't exist
if [[ ! -f ~/.ssh/k3s-cluster ]]; then
    info "Generating SSH key..."
    ssh-keygen -t ed25519 -f ~/.ssh/k3s-cluster -N "" -C "k3s@cluster"
fi

# Upload SSH key to Hetzner
if ! hcloud ssh-key describe "$SSH_KEY_NAME" >/dev/null 2>&1; then
    info "Uploading SSH key to Hetzner..."
    hcloud ssh-key create --name "$SSH_KEY_NAME" --public-key-from-file ~/.ssh/k3s-cluster.pub
fi

# Create server if it doesn't exist
SERVER_NAME="k3s-master-1"
if ! hcloud server describe "$SERVER_NAME" >/dev/null 2>&1; then
    info "Creating Hetzner server: $SERVER_NAME"
    
    # Create the server
    hcloud server create \
        --name "$SERVER_NAME" \
        --type "$SERVER_TYPE" \
        --image "$IMAGE" \
        --location "$LOCATION" \
        --ssh-key "$SSH_KEY_NAME" \
        --start-after-create
    
    # Wait for server to be ready
    info "Waiting for server to be ready..."
    sleep 30
    
    # Get server IP
    SERVER_IP=$(hcloud server ip "$SERVER_NAME")
    info "Server created with IP: $SERVER_IP"
    
    # Save server info
    mkdir -p "${SCRIPT_DIR}/.cluster"
    echo "$SERVER_IP" > "${SCRIPT_DIR}/.cluster/master-ip"
    
    # Wait for SSH to be ready
    info "Waiting for SSH to be ready..."
    while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ~/.ssh/k3s-cluster root@"$SERVER_IP" echo "SSH ready" 2>/dev/null; do
        sleep 5
    done
    
    success "Server is ready"
else
    SERVER_IP=$(hcloud server ip "$SERVER_NAME")
    info "Using existing server: $SERVER_NAME ($SERVER_IP)"
fi

# Create Hetzner Cloud Controller Manager secret
info "Creating Hetzner Cloud Controller Manager configuration..."

# Create the secret file
cat > "${SCRIPT_DIR}/.cluster/hcloud-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: hcloud
  namespace: kube-system
stringData:
  token: "$HETZNER_API_TOKEN"
EOF

# Update DNS if domain is provided
if [[ -n "$DOMAIN" ]]; then
    info "Configuring DNS for $DOMAIN..."
    
    # This assumes you have DNS configured elsewhere
    # You might want to use Hetzner DNS or another provider
    warn "Please ensure $DOMAIN points to $SERVER_IP"
    warn "You may need to update your DNS records manually"
fi

# Prepare remote installation script
info "Preparing remote installation..."

# Copy bootstrap files to server
scp -r -i ~/.ssh/k3s-cluster \
    "${SCRIPT_DIR}"/{bootstrap.sh,lib,components,environments} \
    root@"$SERVER_IP":/root/

# Run installation on remote server
info "Running K3s installation on remote server..."
ssh -i ~/.ssh/k3s-cluster root@"$SERVER_IP" << EOF
    cd /root
    export DOMAIN="$DOMAIN"
    export ENVIRONMENT="hetzner"
    export NODE_TYPE="master"
    ./bootstrap.sh --environment hetzner --components base
EOF

# Fetch kubeconfig
info "Fetching kubeconfig..."
scp -i ~/.ssh/k3s-cluster root@"$SERVER_IP":/etc/rancher/k3s/k3s.yaml ~/.kube/config-hetzner

# Update kubeconfig with correct server URL
sed -i.bak "s/127.0.0.1/$SERVER_IP/g" ~/.kube/config-hetzner

info "Hetzner environment setup complete"
info "To use this cluster: export KUBECONFIG=~/.kube/config-hetzner"

# Apply Hetzner-specific configurations
if [[ -f "${SCRIPT_DIR}/.cluster/hcloud-secret.yaml" ]]; then
    export KUBECONFIG=~/.kube/config-hetzner
    kubectl apply -f "${SCRIPT_DIR}/.cluster/hcloud-secret.yaml"
    
    # Install Hetzner Cloud Controller Manager
    kubectl apply -f https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/latest/download/ccm.yaml
fi

success "Hetzner Cloud environment configured"