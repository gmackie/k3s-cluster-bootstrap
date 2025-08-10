#!/bin/bash
set -euo pipefail

# Longhorn Component Installation
# Cloud-native distributed block storage for Kubernetes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="longhorn"
COMPONENT_NAMESPACE="longhorn-system"
LONGHORN_VERSION="v1.5.3"

install_longhorn() {
    info "Installing Longhorn distributed storage..."
    
    # Check prerequisites
    check_longhorn_prerequisites
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Install dependencies
    info "Installing Longhorn dependencies..."
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/prerequisite/longhorn-iscsi-installation.yaml
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/prerequisite/longhorn-nfs-installation.yaml
    
    # Install Longhorn
    info "Deploying Longhorn ${LONGHORN_VERSION}..."
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/longhorn.yaml
    
    # Wait for Longhorn to be ready
    info "Waiting for Longhorn deployment..."
    kubectl wait --for=condition=ready pod -l app=longhorn-manager -n ${COMPONENT_NAMESPACE} --timeout=600s
    kubectl wait --for=condition=ready pod -l app=longhorn-driver-deployer -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Create default storage class configuration
    info "Configuring storage classes..."
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  fromBackup: ""
  fsType: "ext4"
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-retain
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Retain
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  fromBackup: ""
  fsType: "ext4"
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-single-replica
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "1"
  staleReplicaTimeout: "2880"
  fromBackup: ""
  fsType: "ext4"
EOF
    
    # Create ingress for Longhorn UI
    if [[ -n "${DOMAIN:-}" ]]; then
        info "Creating Longhorn UI ingress..."
        envsubst < "${SCRIPT_DIR}/longhorn-ingress.yaml" | kubectl apply -f -
    fi
    
    # Configure Longhorn settings
    info "Configuring Longhorn settings..."
    kubectl patch -n ${COMPONENT_NAMESPACE} configmap longhorn-default-setting --type='json' -p='[
        {"op": "replace", "path": "/data/default-replica-count", "value": "3"},
        {"op": "replace", "path": "/data/backup-target", "value": ""},
        {"op": "replace", "path": "/data/backup-target-credential-secret", "value": ""},
        {"op": "replace", "path": "/data/create-default-disk-labeled-nodes", "value": "true"},
        {"op": "replace", "path": "/data/default-data-locality", "value": "disabled"},
        {"op": "replace", "path": "/data/replica-soft-anti-affinity", "value": "true"},
        {"op": "replace", "path": "/data/storage-over-provisioning-percentage", "value": "100"},
        {"op": "replace", "path": "/data/storage-minimal-available-percentage", "value": "10"},
        {"op": "replace", "path": "/data/upgrade-checker", "value": "false"},
        {"op": "replace", "path": "/data/default-longhorn-static-storage-class", "value": "longhorn-static"},
        {"op": "replace", "path": "/data/node-down-pod-deletion-policy", "value": "delete-both-statefulset-and-deployment-pod"},
        {"op": "replace", "path": "/data/allow-node-drain-with-last-healthy-replica", "value": "true"},
        {"op": "replace", "path": "/data/replica-zone-soft-anti-affinity", "value": "true"},
        {"op": "replace", "path": "/data/volume-attachment-recovery-policy", "value": "wait"}
    ]' || true
    
    # Save configuration
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/longhorn.conf" <<EOF
LONGHORN_UI_URL=https://longhorn.${DOMAIN}
LONGHORN_VERSION=${LONGHORN_VERSION}

# Storage Classes:
# - longhorn: Standard 3-replica storage (default for production)
# - longhorn-retain: Same as above but retains PV after PVC deletion
# - longhorn-single-replica: Single replica for non-critical data

# Backup Configuration:
# To enable backups to S3 (MinIO or external):
# 1. Create backup credential secret:
#    kubectl create secret generic backup-secret -n longhorn-system \\
#      --from-literal=AWS_ACCESS_KEY_ID=<key> \\
#      --from-literal=AWS_SECRET_ACCESS_KEY=<secret>
# 2. Configure backup target in UI or via kubectl:
#    s3://bucket@region/path

# Volume Snapshots:
# Longhorn supports CSI snapshots for point-in-time backups
# kubectl snapshot.storage.k8s.io/v1 volumesnapshot
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/longhorn.conf"
    
    # Create example PVC
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF
    
    success "Longhorn installed successfully!"
    
    # Display access information
    info "Longhorn Access Information:"
    if [[ -n "${DOMAIN:-}" ]]; then
        echo "  UI URL: https://longhorn.${DOMAIN}"
    else
        echo "  Port-forward for UI access:"
        echo "    kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80"
        echo "    Access: http://localhost:8080"
    fi
    echo ""
    echo "Storage Classes Created:"
    echo "  - longhorn: 3 replicas, delete on PVC deletion"
    echo "  - longhorn-retain: 3 replicas, retain on PVC deletion"
    echo "  - longhorn-single-replica: 1 replica for non-critical data"
    echo ""
    echo "Features:"
    echo "  ✓ Distributed block storage"
    echo "  ✓ Synchronous replication"
    echo "  ✓ Automatic volume snapshots"
    echo "  ✓ Backup to S3 (configurable)"
    echo "  ✓ Volume cloning"
    echo "  ✓ Storage over-provisioning"
    echo "  ✓ UI for management"
    echo ""
    echo "Next Steps:"
    echo "  1. Access Longhorn UI"
    echo "  2. Configure backup target (optional)"
    echo "  3. Create recurring snapshot/backup jobs"
    echo "  4. Monitor disk usage and health"
    echo ""
    echo "To make Longhorn the default storage class:"
    echo "  kubectl patch storageclass local-path -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}'"
    echo "  kubectl patch storageclass longhorn -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'"
}

check_longhorn_prerequisites() {
    info "Checking Longhorn prerequisites..."
    
    # Check kernel modules
    local missing_modules=()
    for module in iscsi_tcp nbd; do
        if ! lsmod | grep -q "^${module}"; then
            missing_modules+=("$module")
        fi
    done
    
    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        warn "Missing kernel modules: ${missing_modules[*]}"
        warn "Attempting to load modules..."
        for module in "${missing_modules[@]}"; do
            sudo modprobe "$module" || warn "Failed to load module: $module"
        done
    fi
    
    # Check required packages
    local missing_packages=()
    for pkg in open-iscsi nfs-common; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
            missing_packages+=("$pkg")
        fi
    done
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        warn "Missing packages: ${missing_packages[*]}"
        info "Installing required packages..."
        sudo apt-get update
        sudo apt-get install -y "${missing_packages[@]}" || error "Failed to install required packages"
    fi
    
    # Check node disk space
    local available_space=$(df -BG /var/lib | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_space -lt 10 ]]; then
        warn "Low disk space on /var/lib: ${available_space}GB available"
        warn "Longhorn requires at least 10GB free space per node"
    fi
    
    success "Prerequisites check completed"
}

uninstall_longhorn() {
    info "Uninstalling Longhorn..."
    
    # Delete all Longhorn volumes first
    warn "Deleting all Longhorn volumes..."
    kubectl get pvc --all-namespaces -o json | \
        jq -r '.items[] | select(.spec.storageClassName == "longhorn" or .spec.storageClassName == "longhorn-retain" or .spec.storageClassName == "longhorn-single-replica") | "\(.metadata.namespace) \(.metadata.name)"' | \
        while read ns pvc; do
            kubectl delete pvc -n "$ns" "$pvc"
        done
    
    # Wait for volumes to be deleted
    sleep 30
    
    # Uninstall Longhorn
    kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/longhorn.yaml || true
    kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/prerequisite/longhorn-nfs-installation.yaml || true
    kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/prerequisite/longhorn-iscsi-installation.yaml || true
    
    # Delete storage classes
    kubectl delete storageclass longhorn longhorn-retain longhorn-single-replica || true
    
    # Delete namespace
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "Longhorn uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_longhorn
        ;;
    uninstall)
        uninstall_longhorn
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac