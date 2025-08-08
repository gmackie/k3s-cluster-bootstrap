# MinIO Component

This component installs MinIO, a high-performance S3-compatible object storage system.

## Features

- **S3 Compatible**: Full S3 API compatibility
- **Distributed Mode**: 4-node cluster for high availability
- **Web Console**: Modern UI for bucket and object management
- **Prometheus Metrics**: Built-in monitoring support
- **Multi-tenancy**: Create multiple users and policies
- **Erasure Coding**: Data protection and redundancy
- **Bucket Versioning**: Object version control
- **Lifecycle Policies**: Automated data management

## Architecture

- 4-node distributed MinIO cluster
- Each node has 50Gi storage (200Gi total raw capacity)
- Erasure coding provides ~100Gi usable capacity
- Tolerates up to 1 node failure

## Access Points

- **S3 API**: `https://s3.<domain>` (No authentication required)
- **Console**: `https://s3-console.<domain>` (OAuth protected)

## Default Buckets

The installation creates these buckets:
- `backups`: Cluster backup storage
- `registry`: Container registry backend
- `artifacts`: CI/CD build artifacts
- `data`: General purpose storage

## Client Configuration

### AWS CLI
```bash
# Configure credentials
aws configure set aws_access_key_id admin
aws configure set aws_secret_access_key <password-from-credentials>

# List buckets
aws --endpoint-url https://s3.<domain> s3 ls

# Upload file
aws --endpoint-url https://s3.<domain> s3 cp file.txt s3://data/

# Download file
aws --endpoint-url https://s3.<domain> s3 cp s3://data/file.txt .
```

### MinIO Client (mc)
```bash
# Set up alias
mc alias set mycluster https://s3.<domain> admin <password>

# List buckets
mc ls mycluster

# Create bucket
mc mb mycluster/mybucket

# Upload file
mc cp file.txt mycluster/mybucket/

# Mirror directory
mc mirror ./localdir mycluster/mybucket/dir/
```

### Python (boto3)
```python
import boto3

s3 = boto3.client('s3',
    endpoint_url='https://s3.<domain>',
    aws_access_key_id='admin',
    aws_secret_access_key='<password>'
)

# List buckets
buckets = s3.list_buckets()

# Upload file
s3.upload_file('file.txt', 'data', 'file.txt')

# Download file
s3.download_file('data', 'file.txt', 'downloaded.txt')
```

### Go
```go
import (
    "github.com/minio/minio-go/v7"
    "github.com/minio/minio-go/v7/pkg/credentials"
)

client, err := minio.New("s3.<domain>", &minio.Options{
    Creds:  credentials.NewStaticV4("admin", "<password>", ""),
    Secure: true,
})

// Upload file
_, err = client.FPutObject(ctx, "data", "file.txt", "file.txt", minio.PutObjectOptions{})
```

## Integration Examples

### Harbor Registry Backend
Configure Harbor to use MinIO:
```yaml
storage:
  s3:
    accesskey: admin
    secretkey: <password>
    region: us-east-1
    regionendpoint: https://s3.<domain>
    bucket: registry
    secure: true
    v4auth: true
```

### Velero Backup Storage
```bash
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.5.0 \
    --bucket backups \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=https://s3.<domain>
```

### Drone CI Artifacts
```yaml
steps:
- name: upload
  image: plugins/s3
  settings:
    bucket: artifacts
    endpoint: https://s3.<domain>
    access_key: admin
    secret_key:
      from_secret: minio_secret
    source: dist/**/*
    target: /builds/${DRONE_BUILD_NUMBER}/
```

## User Management

### Create New User
```bash
# Using mc
mc alias set mycluster https://s3.<domain> admin <admin-password>

# Add user
mc admin user add mycluster newuser newpassword

# Attach policy
mc admin policy set mycluster readwrite user=newuser

# Create access key for user
mc admin user svcacct add mycluster newuser
```

### Policy Examples
```bash
# Read-only access to specific bucket
mc admin policy add mycluster readonly-data /path/to/policy.json

# Policy JSON example
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::data/*", "arn:aws:s3:::data"]
  }]
}
```

## Monitoring

MinIO exposes Prometheus metrics at `/minio/v2/metrics/cluster`.

Configure Prometheus scrape:
```yaml
- job_name: minio
  metrics_path: /minio/v2/metrics/cluster
  static_configs:
  - targets: ['minio.minio.svc.cluster.local:9000']
```

Key metrics:
- `minio_cluster_capacity_total_bytes`: Total capacity
- `minio_cluster_capacity_free_bytes`: Available capacity
- `minio_cluster_disk_offline_total`: Offline disks
- `minio_bucket_usage_total_bytes`: Per-bucket usage

## Backup and Recovery

### Backup MinIO Data
```bash
# Using mc mirror
mc mirror --overwrite mycluster/backups /local/backup/path

# Using restic with MinIO backend
restic -r s3:https://s3.<domain>/backups init
restic backup /important/data
```

### Disaster Recovery
1. MinIO data is stored in PersistentVolumes
2. 4-node cluster tolerates 1 node failure
3. For complete recovery, restore PVs and secrets

## Performance Tuning

### Client Optimization
```bash
# Increase part size for large files (default 5MB)
aws configure set s3.max_concurrent_requests 10
aws configure set s3.max_bandwidth 100MB/s
aws configure set s3.multipart_threshold 64MB
aws configure set s3.multipart_chunksize 16MB
```

### Server Tuning
Environment variables in deployment:
- `MINIO_STORAGE_CLASS_STANDARD`: Set erasure coding (default: EC:2)
- `MINIO_CACHE`: Enable caching for frequently accessed objects
- `MINIO_BROWSER_REDIRECT_URL`: Console URL configuration

## Security

### Encryption
- TLS encryption in transit (ingress)
- Server-side encryption available
- Client-side encryption supported

### Access Control
- IAM-compatible policies
- Bucket policies
- Anonymous access configurable per bucket

### Network Policies
```yaml
# Restrict access to MinIO
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: minio-ingress
  namespace: minio
spec:
  podSelector:
    matchLabels:
      app: minio
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    - namespaceSelector:
        matchLabels:
          name: harbor
```

## Troubleshooting

### Check cluster status
```bash
mc admin info mycluster
```

### View logs
```bash
kubectl logs -n minio statefulset/minio
```

### Heal cluster
```bash
mc admin heal -r mycluster
```

### Common Issues

1. **"Connection refused" errors**
   - Check ingress configuration
   - Verify TLS certificates
   - Ensure all pods are running

2. **"Access Denied" errors**
   - Verify credentials
   - Check bucket policies
   - Ensure user has correct permissions

3. **Slow uploads**
   - Increase multipart chunk size
   - Check network bandwidth
   - Monitor disk I/O on nodes