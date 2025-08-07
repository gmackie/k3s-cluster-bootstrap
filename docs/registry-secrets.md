# Container Registry and Secrets Management

## Overview

The cluster includes Harbor as a full-featured container registry and Sealed Secrets for secure secrets management.

## Harbor Registry

### Features
- **Container Registry**: Store and manage Docker images
- **Vulnerability Scanning**: Automatic scanning with Trivy
- **RBAC**: Project-based access control
- **Replication**: Mirror images between registries
- **Proxy Cache**: Cache images from Docker Hub
- **Helm Charts**: Built-in Helm chart repository
- **Web UI**: User-friendly management interface

### Access Information
- **URL**: `https://<domain>` (e.g., `https://registry.gmac.io`)
- **Admin User**: `admin`
- **Password**: Stored in `.cluster/credentials/registry.conf`

### Docker Configuration

#### Login to Registry
```bash
# Read credentials
source .cluster/credentials/registry.conf

# Login with Docker
docker login $HARBOR_URL -u admin -p $HARBOR_ADMIN_PASSWORD

# Or use the helper script
./scripts/configure-registry.sh test
```

#### Push Images
```bash
# Tag your image
docker tag myapp:latest registry.gmac.io/k3s-system/myapp:latest

# Push to registry
docker push registry.gmac.io/k3s-system/myapp:latest
```

#### Pull Images
```bash
# From within cluster (uses internal DNS)
docker pull registry.registry.svc.cluster.local/k3s-system/myapp:latest

# From outside cluster
docker pull registry.gmac.io/k3s-system/myapp:latest
```

### Projects

Harbor organizes images into projects:

| Project | Visibility | Purpose |
|---------|------------|---------|
| `k3s-system` | Private | System and infrastructure images |
| `public` | Public | Shared images accessible without auth |
| `dockerhub-proxy` | Public | Proxy cache for Docker Hub |

### Kubernetes Integration

#### Configure Namespace Access
```bash
# Setup registry access for a namespace
./scripts/configure-registry.sh setup my-namespace

# This will:
# 1. Create docker-registry secret
# 2. Patch default service account
# 3. Create sealed secret for GitOps
```

#### Using Private Images in Deployments
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: registry.gmac.io/k3s-system/myapp:latest
      imagePullSecrets:
      - name: regcred
```

### Proxy Cache Usage

Pull images through Harbor's proxy cache:
```bash
# Instead of: docker pull nginx:latest
docker pull registry.gmac.io/dockerhub-proxy/library/nginx:latest

# This caches the image in Harbor for faster subsequent pulls
```

### Security Scanning

All images pushed to Harbor are automatically scanned for vulnerabilities:

1. **Automatic Scanning**: Enabled by default
2. **Scan Results**: Visible in Harbor UI
3. **Policies**: Can block pulling of vulnerable images
4. **Reports**: Export vulnerability reports

### Garbage Collection

Configured to run weekly to clean up:
- Untagged images
- Deleted repositories
- Orphaned blobs

## Sealed Secrets

### Overview
Sealed Secrets encrypts Kubernetes secrets so they can be safely stored in Git repositories.

### How It Works
1. Create a regular Kubernetes secret
2. Encrypt it with the cluster's public key
3. Only the cluster can decrypt it
4. Safe to commit to Git

### Creating Sealed Secrets

#### Method 1: Using Helper Script
```bash
# Create and seal a secret in one command
./scripts/manage-secrets.sh create my-secret \
  --from-literal=username=admin \
  --from-literal=password=secret123

# This creates: my-secret-sealed.yaml
```

#### Method 2: Manual Sealing
```bash
# Create a regular secret
kubectl create secret generic my-secret \
  --from-literal=key=value \
  --dry-run=client -o yaml > secret.yaml

# Seal it
./scripts/seal-secret.sh secret.yaml

# This creates: secret-sealed.yaml
```

#### Method 3: From File
```bash
# Create secret from file
kubectl create secret generic app-config \
  --from-file=config.json \
  --dry-run=client -o yaml | ./scripts/seal-secret.sh -
```

### Using Sealed Secrets

1. **Apply Sealed Secret**:
   ```bash
   kubectl apply -f my-secret-sealed.yaml
   ```

2. **Verify Decryption**:
   ```bash
   kubectl get secret my-secret -o yaml
   ```

3. **Use in Pods**:
   ```yaml
   apiVersion: v1
   kind: Pod
   spec:
     containers:
     - name: app
       env:
       - name: API_KEY
         valueFrom:
           secretKeyRef:
             name: my-secret
             key: api-key
   ```

### Secret Templates

Pre-configured templates in `templates/secrets/`:
- `registry-creds.yaml` - Docker registry credentials
- `database-creds.yaml` - Database connection strings
- `api-keys.yaml` - External API keys
- `tls-cert.yaml` - TLS certificates

### Backup and Recovery

#### Backup Master Key (CRITICAL!)
```bash
# Backup the master encryption key
./scripts/manage-secrets.sh backup /secure/backup/location/

# This backs up:
# - sealed-secrets-key.yaml (master key)
# - sealed-secrets-pub.pem (public cert)
# - Restore instructions
```

⚠️ **WARNING**: Keep this backup extremely secure! Anyone with the master key can decrypt all sealed secrets.

#### Restore Master Key
```bash
# On new cluster, restore the key
kubectl apply -f /backup/location/sealed-secrets-key.yaml

# Restart controller to load key
kubectl delete pod -n kube-system -l name=sealed-secrets-controller
```

### Best Practices

1. **Never Commit Unsealed Secrets**
   - Only commit `.yaml` files with `kind: SealedSecret`
   - Add `*-secret.yaml` to `.gitignore`

2. **Rotate Secrets Regularly**
   - Re-seal secrets periodically
   - Update passwords and API keys

3. **Namespace Isolation**
   - Sealed secrets are namespace-specific by default
   - Cannot be moved between namespaces

4. **Backup Master Key**
   - Immediately after installation
   - Store in secure, encrypted location
   - Test restore procedure

## Integration Examples

### CI/CD Pipeline with Private Registry

```yaml
# .gitlab-ci.yml or similar
build:
  script:
    - docker build -t $REGISTRY_URL/project/app:$CI_COMMIT_SHA .
    - echo $REGISTRY_PASSWORD | docker login $REGISTRY_URL -u $REGISTRY_USER --password-stdin
    - docker push $REGISTRY_URL/project/app:$CI_COMMIT_SHA

deploy:
  script:
    - kubectl set image deployment/app app=$REGISTRY_URL/project/app:$CI_COMMIT_SHA
```

### GitOps with Sealed Secrets

```yaml
# apps/my-app/sealed-secrets.yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: app-secrets
  namespace: production
spec:
  encryptedData:
    api-key: AgBy3i4OJSWK+PiTySYZZA9...
    db-password: AgABcD3i4OJSWK+PiTySYZ...
```

### Automated Secret Rotation

```bash
#!/bin/bash
# rotate-secrets.sh

# Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# Create new sealed secret
kubectl create secret generic db-password \
  --from-literal=password="$NEW_PASSWORD" \
  --dry-run=client -o yaml | \
  ./scripts/seal-secret.sh - > new-db-password-sealed.yaml

# Apply new secret
kubectl apply -f new-db-password-sealed.yaml

# Update application
kubectl rollout restart deployment/database-app
```

## Troubleshooting

### Registry Issues

**Cannot push images**:
```bash
# Check login
docker login registry.gmac.io

# Verify project exists
curl -u admin:password https://registry.gmac.io/api/v2.0/projects

# Check disk space
kubectl exec -n registry deployment/harbor-registry -- df -h
```

**Image pull errors in pods**:
```bash
# Verify secret exists
kubectl get secret regcred -n <namespace>

# Check secret is valid
kubectl get secret regcred -o yaml | base64 -d

# Verify service account
kubectl get sa default -n <namespace> -o yaml
```

### Sealed Secrets Issues

**Cannot decrypt secret**:
```bash
# Check controller is running
kubectl get pods -n kube-system -l name=sealed-secrets-controller

# View controller logs
kubectl logs -n kube-system -l name=sealed-secrets-controller

# Verify secret was created
kubectl get secrets
```

**Sealing fails**:
```bash
# Update public certificate
kubeseal --fetch-cert > .cluster/sealed-secrets-pub.pem

# Check kubeseal version matches controller
kubeseal --version
```