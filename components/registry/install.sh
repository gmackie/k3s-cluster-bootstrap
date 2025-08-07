#!/bin/bash
# Container Registry installation with Harbor

source "${SCRIPT_DIR}/lib/common.sh"

info "Installing Harbor container registry..."

# Create namespace
ensure_namespace registry

# Generate passwords and secrets
HARBOR_ADMIN_PASSWORD=$(generate_password)
HARBOR_DB_PASSWORD=$(generate_password)
HARBOR_REDIS_PASSWORD=$(generate_password)
REGISTRY_SECRET=$(openssl rand -base64 32)

# Save credentials
mkdir -p "${SCRIPT_DIR}/.cluster/credentials"
cat > "${SCRIPT_DIR}/.cluster/credentials/registry.conf" <<EOF
HARBOR_ADMIN_USER=admin
HARBOR_ADMIN_PASSWORD=$HARBOR_ADMIN_PASSWORD
HARBOR_URL=https://registry.${DOMAIN:-registry.local}
REGISTRY_SECRET=$REGISTRY_SECRET
EOF
chmod 600 "${SCRIPT_DIR}/.cluster/credentials/registry.conf"

# Add Harbor Helm repository
helm repo add harbor https://helm.goharbor.io
helm repo update

# Create Harbor values
cat > /tmp/harbor-values.yaml <<EOF
# Expose configuration
expose:
  type: clusterIP  # We'll create our own ingress with OAuth
  tls:
    enabled: false

# External URL
externalURL: https://registry.${DOMAIN:-registry.local}

# Persistence configuration
persistence:
  enabled: true
  persistentVolumeClaim:
    registry:
      storageClass: ${STORAGE_CLASS:-local-path}
      size: 50Gi
    chartmuseum:
      storageClass: ${STORAGE_CLASS:-local-path}
      size: 5Gi
    jobservice:
      storageClass: ${STORAGE_CLASS:-local-path}
      size: 5Gi
    database:
      storageClass: ${STORAGE_CLASS:-local-path}
      size: 5Gi
    redis:
      storageClass: ${STORAGE_CLASS:-local-path}
      size: 5Gi
    trivy:
      storageClass: ${STORAGE_CLASS:-local-path}
      size: 5Gi

# Harbor admin password
harborAdminPassword: "$HARBOR_ADMIN_PASSWORD"

# Database
database:
  type: internal
  internal:
    password: "$HARBOR_DB_PASSWORD"

# Redis
redis:
  type: internal
  internal:
    password: "$HARBOR_REDIS_PASSWORD"

# Core component
core:
  secret: "$REGISTRY_SECRET"
  xsrfKey: "$(openssl rand -base64 32)"

# Jobservice
jobservice:
  secret: "$(openssl rand -base64 32)"

# Registry
registry:
  secret: "$(openssl rand -base64 32)"
  credentials:
    username: "harbor_registry_user"
    password: "$(generate_password)"

# Trivy security scanner
trivy:
  enabled: true
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 1Gi

# ChartMuseum (Helm chart repository)
chartmuseum:
  enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Notary (content trust)
notary:
  enabled: false  # Enable if you need image signing

# Metrics
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: monitoring

# Resources
core:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 1Gi

jobservice:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 1Gi

registry:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 2Gi

portal:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
EOF

# Install Harbor
info "Installing Harbor via Helm..."
helm upgrade --install harbor harbor/harbor \
  -f /tmp/harbor-values.yaml \
  -n registry \
  --wait \
  --timeout 10m

# Wait for Harbor to be ready
wait_for_deployment registry harbor-core
wait_for_deployment registry harbor-jobservice
wait_for_deployment registry harbor-portal
wait_for_deployment registry harbor-registry

# Create default project for cluster images
info "Configuring Harbor projects..."

# Wait for Harbor API to be ready
sleep 30

# Create system project
curl -X POST "https://${DOMAIN:-registry.local}/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -u "admin:$HARBOR_ADMIN_PASSWORD" \
  -d '{
    "project_name": "k3s-system",
    "metadata": {
      "public": "false",
      "enable_content_trust": "false",
      "auto_scan": "true",
      "severity": "high",
      "reuse_sys_cve_allowlist": "true"
    }
  }' || true

# Create public project for shared images
curl -X POST "https://${DOMAIN:-registry.local}/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -u "admin:$HARBOR_ADMIN_PASSWORD" \
  -d '{
    "project_name": "public",
    "metadata": {
      "public": "true",
      "enable_content_trust": "false",
      "auto_scan": "true"
    }
  }' || true

# Configure image pull secrets for Kubernetes
info "Creating image pull secrets..."

# Create docker registry secret for each namespace
for ns in default kube-system monitoring gitea control-panel backup; do
  kubectl create secret docker-registry regcred \
    --docker-server="${DOMAIN:-registry.local}" \
    --docker-username=admin \
    --docker-password="$HARBOR_ADMIN_PASSWORD" \
    --docker-email=admin@${DOMAIN:-registry.local} \
    -n $ns \
    --dry-run=client -o yaml | kubectl apply -f -
done

# Create service account with image pull secret
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: default
imagePullSecrets:
- name: regcred
EOF

# Configure garbage collection
info "Configuring garbage collection..."
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: harbor-gc
  namespace: registry
spec:
  schedule: "0 2 * * 0"  # Weekly on Sunday at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: gc
            image: curlimages/curl:latest
            command:
            - /bin/sh
            - -c
            - |
              curl -X POST "https://harbor-core.registry/api/v2.0/system/gc/schedule" \
                -H "Content-Type: application/json" \
                -u "admin:$HARBOR_ADMIN_PASSWORD" \
                -d '{
                  "schedule": {
                    "type": "Weekly",
                    "weekday": 0,
                    "offtime": 7200
                  },
                  "job_parameters": {
                    "delete_untagged": true,
                    "dry_run": false
                  }
                }'
EOF

# Create proxy cache projects for common registries
info "Setting up proxy cache for Docker Hub..."
curl -X POST "https://${DOMAIN:-registry.local}/api/v2.0/registries" \
  -H "Content-Type: application/json" \
  -u "admin:$HARBOR_ADMIN_PASSWORD" \
  -d '{
    "name": "docker-hub",
    "type": "docker-hub",
    "url": "https://hub.docker.com",
    "description": "Docker Hub proxy cache"
  }' || true

# Create proxy project
curl -X POST "https://${DOMAIN:-registry.local}/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -u "admin:$HARBOR_ADMIN_PASSWORD" \
  -d '{
    "project_name": "dockerhub-proxy",
    "registry_id": 1,
    "metadata": {
      "public": "true",
      "enable_content_trust": "false",
      "auto_scan": "false"
    }
  }' || true

# Deploy ingress with OAuth2 authentication
if [[ -n "${DOMAIN:-}" ]]; then
    info "Deploying Harbor ingress with OAuth2 authentication..."
    envsubst < "${SCRIPT_DIR}/harbor-ingress.yaml" | kubectl apply -f -
fi

# Clean up
rm -f /tmp/harbor-values.yaml

success "Harbor registry installed successfully"
info "=== Harbor Access Information ==="
info "URL: https://registry.${DOMAIN:-registry.local}"
info "Username: admin"
info "Password: Saved to .cluster/credentials/registry.conf"
info ""
info "=== Docker Login ==="
info "docker login ${DOMAIN:-registry.local}"
info ""
info "=== Push Image Example ==="
info "docker tag myapp:latest ${DOMAIN:-registry.local}/k3s-system/myapp:latest"
info "docker push ${DOMAIN:-registry.local}/k3s-system/myapp:latest"
info ""
info "=== Features Enabled ==="
info "✓ Container registry with web UI"
info "✓ Vulnerability scanning with Trivy"
info "✓ Helm chart repository"
info "✓ RBAC and project isolation"
info "✓ Proxy cache for Docker Hub"
info "✓ Metrics and monitoring"