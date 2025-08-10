#!/bin/bash
# Storage configuration module

source "${SCRIPT_DIR}/lib/common.sh"

info "Configuring storage..."

# Determine storage type
STORAGE_TYPE="${STORAGE_TYPE:-local}"
STORAGE_SIZE="${STORAGE_SIZE:-100Gi}"

case $STORAGE_TYPE in
    local)
        info "Configuring local storage..."
        configure_local_storage
        ;;
    longhorn)
        info "Longhorn will be installed as a separate component..."
        configure_local_storage  # Use local-path as temporary default
        info "Run './bootstrap.sh --components longhorn' to install Longhorn distributed storage"
        ;;
    nfs)
        info "Configuring NFS storage..."
        configure_nfs_storage
        ;;
    hetzner-volume)
        info "Configuring Hetzner volume storage..."
        configure_hetzner_volume
        ;;
    *)
        error "Unknown storage type: $STORAGE_TYPE"
        ;;
esac

# Configure local storage
configure_local_storage() {
    info "Setting up local-path storage class..."
    
    # K3s comes with local-path-provisioner by default
    # Just ensure it's the default storage class
    kubectl patch storageclass local-path \
        -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    
    # Create additional directories for persistent storage
    sudo mkdir -p /var/lib/k3s-storage/{gitea,prometheus,grafana,registry}
    sudo chmod 755 /var/lib/k3s-storage
    
    success "Local storage configured"
}

# Configure NFS storage
configure_nfs_storage() {
    NFS_SERVER="${NFS_SERVER:-}"
    NFS_PATH="${NFS_PATH:-/k3s-storage}"
    
    if [[ -z "$NFS_SERVER" ]]; then
        read -p "Enter NFS server address: " NFS_SERVER
    fi
    
    info "Installing NFS client provisioner..."
    
    # Add NFS provisioner helm repo
    helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
    helm repo update
    
    # Install NFS provisioner
    helm upgrade --install nfs-provisioner \
        nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
        --set nfs.server="$NFS_SERVER" \
        --set nfs.path="$NFS_PATH" \
        --set storageClass.name=nfs-storage \
        --set storageClass.defaultClass=true \
        -n kube-system \
        --wait
    
    success "NFS storage configured with server: $NFS_SERVER"
}

# Configure Hetzner volume storage
configure_hetzner_volume() {
    if [[ "$ENVIRONMENT" != "hetzner" ]]; then
        error "Hetzner volume storage requires Hetzner environment"
    fi
    
    info "Installing Hetzner CSI driver..."
    
    # Create CSI driver secret
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: hcloud-csi
  namespace: kube-system
stringData:
  token: "$HETZNER_API_TOKEN"
EOF
    
    # Install Hetzner CSI driver
    kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/v2.5.1/deploy/kubernetes/hcloud-csi.yml
    
    # Wait for CSI driver to be ready
    wait_for_deployment kube-system hcloud-csi-controller
    
    # Create storage class
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hcloud-volumes
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.hetzner.cloud
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  csi.storage.k8s.io/fstype: ext4
EOF
    
    success "Hetzner volume storage configured"
}

# Create backup storage configuration
info "Creating backup storage configuration..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: backup-config
  namespace: kube-system
data:
  backup-schedule: "0 2 * * *"  # Daily at 2 AM
  retention-days: "30"
  backup-targets: |
    - gitea-data
    - prometheus-data
    - grafana-data
    - control-panel-data
EOF

# Create storage monitoring
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: storage-metrics
  namespace: kube-system
  labels:
    app: storage-metrics
spec:
  ports:
  - port: 9100
    name: metrics
  selector:
    app: node-exporter
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: storage-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: storage-metrics
  endpoints:
  - port: metrics
    path: /metrics
    relabelings:
    - sourceLabels: [__meta_kubernetes_pod_node_name]
      targetLabel: node
EOF

# Storage health check script
cat > "${SCRIPT_DIR}/.cluster/check-storage.sh" <<'EOF'
#!/bin/bash
# Storage health check script

echo "Checking storage health..."

# Check storage classes
echo -e "\nStorage Classes:"
kubectl get storageclass

# Check PVCs
echo -e "\nPersistent Volume Claims:"
kubectl get pvc --all-namespaces

# Check PVs
echo -e "\nPersistent Volumes:"
kubectl get pv

# Check disk usage on nodes
echo -e "\nNode disk usage:"
kubectl get nodes -o json | jq -r '.items[] | .metadata.name' | while read node; do
    echo "Node: $node"
    kubectl get --raw "/api/v1/nodes/$node/proxy/stats/summary" | \
        jq -r '.node.fs | "  Root FS: \(.capacityBytes/1024/1024/1024 | round)GB total, \(.availableBytes/1024/1024/1024 | round)GB available"'
done
EOF

chmod +x "${SCRIPT_DIR}/.cluster/check-storage.sh"

success "Storage configuration complete"
info "Storage type: $STORAGE_TYPE"
info "Run .cluster/check-storage.sh to check storage health"