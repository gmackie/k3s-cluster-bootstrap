#!/bin/bash
set -euo pipefail

# MinIO Component Installation
# S3-compatible object storage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="minio"
COMPONENT_NAMESPACE="minio"

install_minio() {
    info "Installing MinIO S3-compatible storage..."
    
    if [[ -z "${DOMAIN:-}" ]]; then
        error "Domain is required for MinIO installation"
        echo "Please specify --domain when running bootstrap.sh"
        exit 1
    fi
    
    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate credentials
    MINIO_ROOT_USER="admin"
    MINIO_ROOT_PASSWORD=$(generate_password 32)
    
    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/minio.conf" <<EOF
MINIO_API_URL=https://s3.${DOMAIN}
MINIO_CONSOLE_URL=https://s3-console.${DOMAIN}
MINIO_ROOT_USER=$MINIO_ROOT_USER
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD

# S3 Client Configuration
export AWS_ACCESS_KEY_ID=$MINIO_ROOT_USER
export AWS_SECRET_ACCESS_KEY=$MINIO_ROOT_PASSWORD
export AWS_ENDPOINT_URL=https://s3.${DOMAIN}

# mc (MinIO Client) alias
# mc alias set mycluster https://s3.${DOMAIN} $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/minio.conf"
    
    # Create secrets
    kubectl create secret generic minio-secrets \
        --namespace=${COMPONENT_NAMESPACE} \
        --from-literal=root-user="${MINIO_ROOT_USER}" \
        --from-literal=root-password="${MINIO_ROOT_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy MinIO
    info "Deploying MinIO distributed mode..."
    envsubst < "${SCRIPT_DIR}/minio-statefulset.yaml" | kubectl apply -f -
    kubectl apply -f "${SCRIPT_DIR}/minio-service.yaml"
    envsubst < "${SCRIPT_DIR}/minio-ingress.yaml" | kubectl apply -f -
    
    # Wait for StatefulSet
    info "Waiting for MinIO pods..."
    kubectl rollout status statefulset/minio -n ${COMPONENT_NAMESPACE} --timeout=300s
    
    # Create default buckets
    info "Creating default buckets..."
    sleep 10  # Give MinIO time to fully initialize
    
    # Create a job to initialize buckets
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: minio-init-buckets
  namespace: ${COMPONENT_NAMESPACE}
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: mc
        image: minio/mc:latest
        command:
        - /bin/sh
        - -c
        - |
          mc alias set minio http://minio:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD
          mc mb --ignore-existing minio/backups
          mc mb --ignore-existing minio/registry
          mc mb --ignore-existing minio/artifacts
          mc mb --ignore-existing minio/data
          mc admin user add minio backup-user \$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)
          mc admin policy set minio readwrite user=backup-user
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-secrets
              key: root-user
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-secrets
              key: root-password
EOF
    
    # Wait for job completion
    kubectl wait --for=condition=complete job/minio-init-buckets -n ${COMPONENT_NAMESPACE} --timeout=60s || true
    
    success "MinIO installed successfully!"
    
    # Display access information
    info "MinIO Access Information:"
    echo "  S3 API Endpoint: https://s3.${DOMAIN}"
    echo "  Console URL: https://s3-console.${DOMAIN}"
    echo "  Root User: ${MINIO_ROOT_USER}"
    echo "  Root Password: Saved in credentials file"
    echo ""
    echo "Client Configuration:"
    echo "  AWS CLI:"
    echo "    aws configure set aws_access_key_id ${MINIO_ROOT_USER}"
    echo "    aws configure set aws_secret_access_key <password-from-credentials>"
    echo "    aws --endpoint-url https://s3.${DOMAIN} s3 ls"
    echo ""
    echo "  MinIO Client (mc):"
    echo "    mc alias set mycluster https://s3.${DOMAIN} ${MINIO_ROOT_USER} <password>"
    echo "    mc ls mycluster"
    echo ""
    echo "Default Buckets Created:"
    echo "  - backups: For cluster backups"
    echo "  - registry: For container registry storage"
    echo "  - artifacts: For build artifacts"
    echo "  - data: General purpose storage"
    echo ""
    echo "Integration Examples:"
    echo "  Harbor Registry: Use 'registry' bucket for storage"
    echo "  Velero Backup: Use 'backups' bucket"
    echo "  CI/CD Artifacts: Use 'artifacts' bucket"
    echo ""
    echo "Credentials saved to: ${SCRIPT_DIR}/../../.cluster/credentials/minio.conf"
}

uninstall_minio() {
    info "Uninstalling MinIO..."
    
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found
    
    success "MinIO uninstalled successfully!"
}

# Main execution
case "${1:-install}" in
    install)
        install_minio
        ;;
    uninstall)
        uninstall_minio
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac