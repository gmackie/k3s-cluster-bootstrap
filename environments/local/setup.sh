#!/bin/bash
# Local environment setup

source "${SCRIPT_DIR}/lib/common.sh"

info "Setting up local environment..."

# Check system requirements
check_requirements

# Check if running as root (not recommended)
if [[ $EUID -eq 0 ]]; then
   warn "Running as root is not recommended. Consider using a regular user with sudo privileges."
fi

# Update system packages
info "Updating system packages..."
if [[ -f /etc/debian_version ]]; then
    sudo apt-get update
    sudo apt-get install -y curl wget git
elif [[ -f /etc/redhat-release ]]; then
    sudo yum update -y
    sudo yum install -y curl wget git
fi

# Configure firewall if needed
if command_exists ufw; then
    info "Configuring firewall..."
    sudo ufw allow 6443/tcp  # K3s API
    sudo ufw allow 10250/tcp # Kubelet metrics
    sudo ufw allow 80/tcp    # HTTP
    sudo ufw allow 443/tcp   # HTTPS
    
    # For multi-node clusters
    if [[ "$NODE_TYPE" == "master" ]]; then
        sudo ufw allow 2379:2380/tcp  # etcd
        sudo ufw allow 10251/tcp      # kube-scheduler
        sudo ufw allow 10252/tcp      # kube-controller
    fi
fi

# Set up local storage directory
info "Setting up local storage..."
sudo mkdir -p /var/lib/k3s-storage
sudo chmod 755 /var/lib/k3s-storage

# For local development, we might want to set up a local domain
if [[ -n "$DOMAIN" && "$DOMAIN" == *.local ]]; then
    info "Configuring local domain: $DOMAIN"
    
    # Add to /etc/hosts
    if ! grep -q "$DOMAIN" /etc/hosts; then
        echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts
        echo "127.0.0.1 git.$DOMAIN" | sudo tee -a /etc/hosts
        echo "127.0.0.1 grafana.$DOMAIN" | sudo tee -a /etc/hosts
    fi
fi

# Create configuration directory
mkdir -p "${SCRIPT_DIR}/.cluster"

# Save environment configuration
cat > "${SCRIPT_DIR}/.cluster/environment.conf" <<EOF
ENVIRONMENT=local
DOMAIN=$DOMAIN
NODE_TYPE=$NODE_TYPE
SETUP_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF

success "Local environment setup complete"