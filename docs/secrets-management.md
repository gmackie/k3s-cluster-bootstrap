# Secrets Management with Sealed Secrets

This cluster uses Bitnami Sealed Secrets for secure secret management in GitOps workflows.

## Overview

Sealed Secrets allows you to encrypt secrets that can be stored safely in Git. Only the cluster can decrypt them.

## Installation

Sealed Secrets is installed automatically when you include `sealed-secrets` in the bootstrap components:

```bash
./bootstrap-v3.sh --components base,storage,auth,sealed-secrets,argocd
```

Or select it during interactive setup.

## Usage

### 1. Create a Regular Secret

```bash
kubectl create secret generic my-secret \
  --from-literal=username=myuser \
  --from-literal=password=mypassword \
  --dry-run=client -o yaml > secret.yaml
```

### 2. Seal the Secret

```bash
# Using the cluster's public key
kubeseal < secret.yaml > sealed-secret.yaml

# Or with the downloaded public key (for CI/CD)
kubeseal --cert .cluster/sealed-secrets-public.pem < secret.yaml > sealed-secret.yaml
```

### 3. Apply the Sealed Secret

```bash
kubectl apply -f sealed-secret.yaml
```

The controller will decrypt it and create a regular Secret in the cluster.

## NPM Registry CI Credentials

NPM registry credentials for CI/CD are pre-configured:

```bash
# Create sealed secrets for npm registry
./create-npm-sealed-secret.sh
```

This creates sealed secrets in multiple namespaces:
- `default` - For general use
- `argocd` - For ArgoCD deployments
- `gitea` - For Gitea CI runners

## GitHub Actions Integration

Add these secrets to your GitHub repository:
- `NPM_REGISTRY`: https://npm.gmac.io
- `NPM_TOKEN`: (get from .cluster/credentials/npm-registry.conf)

Example workflow:

```yaml
name: Build and Publish
on: push

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure NPM Registry
        run: |
          echo "//${{ secrets.NPM_REGISTRY#https:// }}/:_authToken=${{ secrets.NPM_TOKEN }}" > ~/.npmrc
          npm config set @yourscope:registry ${{ secrets.NPM_REGISTRY }}
      
      - name: Install Dependencies
        run: npm ci
      
      - name: Build
        run: npm run build
      
      - name: Publish
        run: npm publish
```

## Kubernetes Deployment Usage

In your Kubernetes manifests:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: NPM_TOKEN
      valueFrom:
        secretKeyRef:
          name: npm-registry-ci
          key: NPM_TOKEN
    volumeMounts:
    - name: npmrc
      mountPath: /root/.npmrc
      subPath: .npmrc
  volumes:
  - name: npmrc
    secret:
      secretName: npm-registry-ci
      items:
      - key: NPMRC
        path: .npmrc
```

## Backup

**IMPORTANT**: Back up the sealing key from the cluster:

```bash
kubectl get secret -n sealed-secrets sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml
```

Store this backup securely. Without it, you cannot decrypt your secrets if the cluster is rebuilt.

## Scopes

Sealed Secrets can be scoped:
- **strict** (default): Can only be decrypted in the same namespace and with the same name
- **namespace-wide**: Can be decrypted in the same namespace with any name
- **cluster-wide**: Can be decrypted anywhere in the cluster

Example with cluster-wide scope:
```bash
kubeseal --scope cluster-wide < secret.yaml > sealed-secret.yaml
```

## Troubleshooting

Check controller logs:
```bash
kubectl logs -n sealed-secrets deployment/sealed-secrets-controller
```

Verify a sealed secret:
```bash
kubeseal --validate < sealed-secret.yaml
```