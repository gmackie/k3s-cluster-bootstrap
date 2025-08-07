#!/bin/bash
# Backup and disaster recovery installation

source "${SCRIPT_DIR}/lib/common.sh"

info "Installing backup and disaster recovery system..."

# Create namespace
ensure_namespace backup

# Install Velero for cluster backup
info "Installing Velero backup solution..."

# Download Velero CLI if not present
if ! command_exists velero; then
    info "Downloading Velero CLI..."
    VELERO_VERSION="v1.12.0"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        curl -L https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-darwin-amd64.tar.gz | tar xz
        sudo mv velero-${VELERO_VERSION}-darwin-amd64/velero /usr/local/bin/
    else
        curl -L https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz | tar xz
        sudo mv velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/
    fi
    rm -rf velero-${VELERO_VERSION}-*
fi

# Configure backup storage
BACKUP_PROVIDER="${BACKUP_PROVIDER:-local}"
BACKUP_BUCKET="${BACKUP_BUCKET:-k3s-backups}"

case $BACKUP_PROVIDER in
    local)
        info "Configuring local backup storage with MinIO..."
        
        # Install MinIO for local S3-compatible storage
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-storage
  namespace: backup
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: ${STORAGE_CLASS:-local-path}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: backup
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        args:
        - server
        - /data
        - --console-address
        - ":9001"
        env:
        - name: MINIO_ROOT_USER
          value: "admin"
        - name: MINIO_ROOT_PASSWORD
          value: "$(generate_password)"
        ports:
        - containerPort: 9000
          name: api
        - containerPort: 9001
          name: console
        volumeMounts:
        - name: storage
          mountPath: /data
        livenessProbe:
          httpGet:
            path: /minio/health/live
            port: api
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /minio/health/ready
            port: api
          initialDelaySeconds: 30
          periodSeconds: 10
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: minio-storage
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: backup
spec:
  selector:
    app: minio
  ports:
  - name: api
    port: 9000
    targetPort: api
  - name: console
    port: 9001
    targetPort: console
EOF
        
        # Wait for MinIO to be ready
        wait_for_deployment backup minio
        
        # Create backup bucket
        kubectl exec -n backup deployment/minio -- \
            mc alias set local http://localhost:9000 admin "$(kubectl get deployment -n backup minio -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MINIO_ROOT_PASSWORD")].value}')"
        kubectl exec -n backup deployment/minio -- \
            mc mb local/${BACKUP_BUCKET} || true
            
        # Configure Velero for MinIO
        velero install \
            --provider aws \
            --plugins velero/velero-plugin-for-aws:v1.8.0 \
            --bucket ${BACKUP_BUCKET} \
            --secret-file /dev/stdin <<EOF
[default]
aws_access_key_id=admin
aws_secret_access_key=$(kubectl get deployment -n backup minio -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MINIO_ROOT_PASSWORD")].value}')
EOF
            --backup-location-config region=minio,s3ForcePathStyle=true,s3Url=http://minio.backup:9000 \
            --use-node-agent \
            --namespace backup
        ;;
        
    s3)
        info "Configuring AWS S3 backup storage..."
        
        read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
        read -sp "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
        echo
        read -p "AWS Region: " AWS_REGION
        read -p "S3 Bucket Name: " S3_BUCKET
        
        # Install Velero with AWS provider
        velero install \
            --provider aws \
            --plugins velero/velero-plugin-for-aws:v1.8.0 \
            --bucket ${S3_BUCKET} \
            --secret-file /dev/stdin <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF
            --backup-location-config region=${AWS_REGION} \
            --use-node-agent \
            --namespace backup
        ;;
        
    azure)
        info "Configuring Azure Blob Storage backup..."
        
        read -p "Azure Storage Account: " AZURE_STORAGE_ACCOUNT
        read -sp "Azure Storage Key: " AZURE_STORAGE_KEY
        echo
        read -p "Container Name: " CONTAINER_NAME
        read -p "Resource Group: " RESOURCE_GROUP
        
        # Install Velero with Azure provider
        velero install \
            --provider azure \
            --plugins velero/velero-plugin-for-microsoft-azure:v1.8.0 \
            --bucket ${CONTAINER_NAME} \
            --secret-file /dev/stdin <<EOF
AZURE_STORAGE_ACCOUNT_ACCESS_KEY=${AZURE_STORAGE_KEY}
AZURE_CLOUD_NAME=AzurePublicCloud
EOF
            --backup-location-config resourceGroup=${RESOURCE_GROUP},storageAccount=${AZURE_STORAGE_ACCOUNT} \
            --use-node-agent \
            --namespace backup
        ;;
esac

# Create backup schedules
info "Creating backup schedules..."

# Daily backup of all namespaces
cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: backup
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  template:
    ttl: 720h  # 30 days retention
    includedNamespaces:
    - "*"
    excludedNamespaces:
    - kube-system
    - kube-public
    - kube-node-lease
    storageLocation: default
    volumeSnapshotLocations:
    - default
---
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: weekly-full-backup
  namespace: backup
spec:
  schedule: "0 3 * * 0"  # 3 AM Sunday
  template:
    ttl: 2160h  # 90 days retention
    includedNamespaces:
    - "*"
    storageLocation: default
    volumeSnapshotLocations:
    - default
---
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: critical-apps-backup
  namespace: backup
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  template:
    ttl: 168h  # 7 days retention
    includedNamespaces:
    - gitea
    - monitoring
    - control-panel
    labelSelector:
      matchLabels:
        backup: critical
    storageLocation: default
    volumeSnapshotLocations:
    - default
EOF

# Install etcd backup CronJob
info "Setting up etcd backup..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: etcd-backup
  namespace: backup
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: etcd-backup
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods", "pods/exec"]
  verbs: ["get", "list", "create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: etcd-backup
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: etcd-backup
subjects:
- kind: ServiceAccount
  name: etcd-backup
  namespace: backup
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: etcd-backup
  namespace: backup
spec:
  schedule: "0 1 * * *"  # 1 AM daily
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: etcd-backup
          containers:
          - name: backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              set -e
              DATE=$(date +%Y%m%d-%H%M%S)
              BACKUP_DIR="/backups/etcd"
              mkdir -p ${BACKUP_DIR}
              
              # Find etcd pod
              ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')
              
              if [ -z "$ETCD_POD" ]; then
                echo "No etcd pod found"
                exit 1
              fi
              
              # Create etcd snapshot
              kubectl exec -n kube-system ${ETCD_POD} -- etcdctl \
                --endpoints=https://127.0.0.1:2379 \
                --cacert=/etc/kubernetes/pki/etcd/ca.crt \
                --cert=/etc/kubernetes/pki/etcd/server.crt \
                --key=/etc/kubernetes/pki/etcd/server.key \
                snapshot save /tmp/etcd-snapshot-${DATE}.db
              
              # Copy snapshot to backup volume
              kubectl cp kube-system/${ETCD_POD}:/tmp/etcd-snapshot-${DATE}.db ${BACKUP_DIR}/etcd-snapshot-${DATE}.db
              
              # Clean up old backups (keep last 7 days)
              find ${BACKUP_DIR} -name "etcd-snapshot-*.db" -mtime +7 -delete
              
              echo "etcd backup completed: etcd-snapshot-${DATE}.db"
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: etcd-backup-storage
          restartPolicy: OnFailure
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: etcd-backup-storage
  namespace: backup
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: ${STORAGE_CLASS:-local-path}
EOF

# Create backup monitoring
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceMonitor
metadata:
  name: velero-metrics
  namespace: backup
  labels:
    app.kubernetes.io/name: velero
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: velero
  endpoints:
  - port: http-monitoring
    path: /metrics
    interval: 30s
EOF

# Save backup configuration
mkdir -p "${SCRIPT_DIR}/.cluster/backup"
cat > "${SCRIPT_DIR}/.cluster/backup/config.yaml" <<EOF
provider: ${BACKUP_PROVIDER}
bucket: ${BACKUP_BUCKET}
schedules:
  - name: daily-backup
    schedule: "0 2 * * *"
    retention: 30d
  - name: weekly-full-backup
    schedule: "0 3 * * 0"
    retention: 90d
  - name: critical-apps-backup
    schedule: "0 */6 * * *"
    retention: 7d
EOF

success "Backup and disaster recovery system installed"
info "Backup schedules created:"
info "  - Daily backup at 2 AM (30-day retention)"
info "  - Weekly full backup on Sunday at 3 AM (90-day retention)"
info "  - Critical apps backup every 6 hours (7-day retention)"
info "  - etcd backup daily at 1 AM (7-day retention)"
info ""
info "Use 'velero backup create <name>' for manual backups"
info "Use 'velero restore create --from-backup <name>' to restore"