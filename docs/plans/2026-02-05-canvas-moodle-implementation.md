# Canvas & Moodle LTI Testing Environment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy Canvas and Moodle LMS platforms on gmac.io cluster for LTI 1.3 integration testing.

**Architecture:** Moodle via Bitnami Helm chart, Canvas via raw manifests with Instructure images. Both get dedicated PostgreSQL instances, Authentik SSO integration, and ingresses at canvas.gmac.io / moodle.gmac.io.

**Tech Stack:** Kubernetes, Helm, PostgreSQL 15, Redis, NGINX Ingress, cert-manager, Authentik OIDC

---

## Task 1: Create Moodle Component Directory Structure

**Files:**
- Create: `components/moodle/install.sh`
- Create: `components/moodle/values.yaml`
- Create: `components/moodle/README.md`

**Step 1: Create the moodle component directory**

```bash
mkdir -p components/moodle
```

**Step 2: Create README.md with component documentation**

Create `components/moodle/README.md`:
```markdown
# Moodle LMS Component

Moodle learning management system for LTI integration testing.

## Features
- Moodle LMS with PostgreSQL backend
- LTI 1.3 + Advantage support
- Authentik SSO integration ready
- Minimal resource footprint

## Prerequisites
- Base cluster components installed
- Longhorn storage available
- Domain configured

## Installation
```bash
export KUBECONFIG=~/.kube/config-hetzner
export DOMAIN=gmac.io
./components/moodle/install.sh
```

## Access
- URL: https://moodle.gmac.io
- Admin credentials: See `.cluster/credentials/moodle.conf`

## LTI 1.3 Configuration
1. Login as admin
2. Site Administration → Plugins → Activity modules → External tool
3. Manage tools → Configure a tool manually
4. Enter your LTI tool details (client ID, deployment ID, etc.)
```

**Step 3: Commit the directory structure**

```bash
git add components/moodle/README.md
git commit -m "chore(moodle): create component directory structure"
```

---

## Task 2: Create Moodle Helm Values File

**Files:**
- Create: `components/moodle/values.yaml`

**Step 1: Create the Helm values file**

Create `components/moodle/values.yaml`:
```yaml
# Moodle Bitnami Helm Chart Values
# Minimal configuration for LTI integration testing

## Moodle configuration
moodleUsername: admin
# moodlePassword: generated at install time
moodleEmail: admin@gmac.io
moodleSiteName: "Moodle LTI Testing"
moodleSkipInstall: false
moodleLang: en

## Resource allocation (minimal)
resources:
  requests:
    cpu: 300m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi

## Persistence
persistence:
  enabled: true
  storageClass: longhorn
  size: 5Gi

## Service configuration
service:
  type: ClusterIP
  port: 80

## Ingress - disabled, we create our own
ingress:
  enabled: false

## PostgreSQL configuration
postgresql:
  enabled: true
  auth:
    # password: generated at install time
    database: moodle
  primary:
    persistence:
      enabled: true
      storageClass: longhorn
      size: 5Gi
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi

## Disable MariaDB (use PostgreSQL)
mariadb:
  enabled: false

## Metrics
metrics:
  enabled: false

## Extra environment variables for LTI support
extraEnvVars:
  - name: MOODLE_PLUGINS_INSTALL
    value: ""
```

**Step 2: Commit the values file**

```bash
git add components/moodle/values.yaml
git commit -m "feat(moodle): add Helm values for minimal LTI testing deployment"
```

---

## Task 3: Create Moodle Install Script

**Files:**
- Create: `components/moodle/install.sh`

**Step 1: Create the install script**

Create `components/moodle/install.sh`:
```bash
#!/bin/bash
set -euo pipefail

# Moodle LMS Installation
# Learning management system for LTI integration testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="moodle"
COMPONENT_NAMESPACE="moodle"

install_moodle() {
    info "Installing Moodle LMS..."

    if [[ -z "${DOMAIN:-}" ]]; then
        error "DOMAIN is required for Moodle installation"
    fi

    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    # Generate passwords
    MOODLE_PASSWORD=$(generate_password)
    POSTGRES_PASSWORD=$(generate_password)

    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/moodle.conf" <<EOF
MOODLE_URL=https://moodle.${DOMAIN}
ADMIN_USER=admin
ADMIN_PASSWORD=${MOODLE_PASSWORD}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# LTI 1.3 Configuration
# After installation, configure LTI tools at:
# Site Administration → Plugins → Activity modules → External tool

# Authentik SSO (manual configuration required)
# 1. Create OIDC provider in Authentik for Moodle
# 2. In Moodle: Site Administration → Plugins → Authentication → OpenID Connect
# 3. Configure with Authentik endpoints
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/moodle.conf"

    # Add Bitnami Helm repo
    info "Adding Bitnami Helm repository..."
    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo update

    # Create temporary values file with passwords
    cat > /tmp/moodle-install-values.yaml <<EOF
moodlePassword: "${MOODLE_PASSWORD}"
postgresql:
  auth:
    password: "${POSTGRES_PASSWORD}"
    postgresPassword: "${POSTGRES_PASSWORD}"
EOF

    # Merge with main values file
    info "Installing Moodle via Helm..."
    helm upgrade --install moodle bitnami/moodle \
        -f "${SCRIPT_DIR}/values.yaml" \
        -f /tmp/moodle-install-values.yaml \
        -n "${COMPONENT_NAMESPACE}" \
        --wait \
        --timeout 15m

    # Clean up temp file
    rm -f /tmp/moodle-install-values.yaml

    # Create ingress
    info "Creating Moodle ingress..."
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: moodle-ingress
  namespace: ${COMPONENT_NAMESPACE}
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - moodle.${DOMAIN}
    secretName: moodle-tls
  rules:
  - host: moodle.${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: moodle
            port:
              number: 80
EOF

    # Wait for ingress to be ready
    info "Waiting for TLS certificate..."
    sleep 10

    success "Moodle installed successfully!"
    info ""
    info "=== Moodle Access Information ==="
    info "URL: https://moodle.${DOMAIN}"
    info "Admin User: admin"
    info "Admin Password: See .cluster/credentials/moodle.conf"
    info ""
    info "=== LTI 1.3 Setup ==="
    info "1. Login as admin"
    info "2. Site Administration → Plugins → Activity modules → External tool"
    info "3. Manage tools → Configure a tool manually"
    info ""
    info "=== Authentik SSO Setup (optional) ==="
    info "1. Create OIDC provider in Authentik for 'Moodle LMS'"
    info "2. In Moodle: Site Administration → Plugins → Authentication → Manage authentication"
    info "3. Enable OAuth 2 authentication"
    info "4. Configure OAuth 2 service with Authentik endpoints"
}

uninstall_moodle() {
    info "Uninstalling Moodle..."

    helm uninstall moodle -n ${COMPONENT_NAMESPACE} --ignore-not-found || true
    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found

    success "Moodle uninstalled!"
}

# Main execution
case "${1:-install}" in
    install)
        install_moodle
        ;;
    uninstall)
        uninstall_moodle
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        ;;
esac
```

**Step 2: Make the script executable**

```bash
chmod +x components/moodle/install.sh
```

**Step 3: Commit the install script**

```bash
git add components/moodle/install.sh
git commit -m "feat(moodle): add installation script with Helm deployment"
```

---

## Task 4: Create Canvas Component Directory Structure

**Files:**
- Create: `components/canvas/README.md`

**Step 1: Create the canvas component directory**

```bash
mkdir -p components/canvas
```

**Step 2: Create README.md**

Create `components/canvas/README.md`:
```markdown
# Canvas LMS Component

Instructure Canvas LMS for LTI integration testing.

## Features
- Canvas LMS with PostgreSQL backend
- Redis for caching and jobs
- LTI 1.3 + Advantage support (Developer Keys)
- Authentik SSO integration ready

## Prerequisites
- Base cluster components installed
- Longhorn storage available
- Domain configured

## Installation
```bash
export KUBECONFIG=~/.kube/config-hetzner
export DOMAIN=gmac.io
./components/canvas/install.sh
```

## Access
- URL: https://canvas.gmac.io
- Admin credentials: See `.cluster/credentials/canvas.conf`

## LTI 1.3 Configuration
1. Login as admin
2. Admin → Developer Keys → + Developer Key → + LTI Key
3. Configure your LTI tool settings
4. Enable the key (toggle to ON)

## Notes
- Canvas is resource-intensive; initial page loads may be slow
- Background jobs process asynchronously via canvas-jobs
- Uses Instructure's community Docker images
```

**Step 3: Commit**

```bash
git add components/canvas/README.md
git commit -m "chore(canvas): create component directory structure"
```

---

## Task 5: Create Canvas PostgreSQL Manifest

**Files:**
- Create: `components/canvas/canvas-postgres.yaml`

**Step 1: Create PostgreSQL manifest**

Create `components/canvas/canvas-postgres.yaml`:
```yaml
# Canvas PostgreSQL Database
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: canvas-postgres-pvc
  namespace: canvas
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: longhorn
---
apiVersion: v1
kind: Secret
metadata:
  name: canvas-postgres-secret
  namespace: canvas
type: Opaque
stringData:
  POSTGRES_USER: canvas
  POSTGRES_PASSWORD: "${CANVAS_DB_PASSWORD}"
  POSTGRES_DB: canvas_production
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: canvas-postgres
  namespace: canvas
spec:
  replicas: 1
  selector:
    matchLabels:
      app: canvas-postgres
  template:
    metadata:
      labels:
        app: canvas-postgres
    spec:
      containers:
      - name: postgres
        image: postgres:12-alpine
        ports:
        - containerPort: 5432
          name: postgres
        envFrom:
        - secretRef:
            name: canvas-postgres-secret
        env:
        - name: PGDATA
          value: "/var/lib/postgresql/data/pgdata"
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          exec:
            command: ["pg_isready", "-U", "canvas"]
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "canvas"]
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: canvas-postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: canvas-postgres
  namespace: canvas
spec:
  selector:
    app: canvas-postgres
  ports:
  - port: 5432
    targetPort: 5432
```

**Step 2: Commit**

```bash
git add components/canvas/canvas-postgres.yaml
git commit -m "feat(canvas): add PostgreSQL database manifest"
```

---

## Task 6: Create Canvas Redis Manifest

**Files:**
- Create: `components/canvas/canvas-redis.yaml`

**Step 1: Create Redis manifest**

Create `components/canvas/canvas-redis.yaml`:
```yaml
# Canvas Redis for caching and job queues
apiVersion: apps/v1
kind: Deployment
metadata:
  name: canvas-redis
  namespace: canvas
spec:
  replicas: 1
  selector:
    matchLabels:
      app: canvas-redis
  template:
    metadata:
      labels:
        app: canvas-redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        livenessProbe:
          exec:
            command: ["redis-cli", "ping"]
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          exec:
            command: ["redis-cli", "ping"]
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: canvas-redis
  namespace: canvas
spec:
  selector:
    app: canvas-redis
  ports:
  - port: 6379
    targetPort: 6379
```

**Step 2: Commit**

```bash
git add components/canvas/canvas-redis.yaml
git commit -m "feat(canvas): add Redis cache manifest"
```

---

## Task 7: Create Canvas Configuration Manifest

**Files:**
- Create: `components/canvas/canvas-config.yaml`

**Step 1: Create Canvas configuration**

Create `components/canvas/canvas-config.yaml`:
```yaml
# Canvas LMS Configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: canvas-config
  namespace: canvas
data:
  # Database configuration
  database.yml: |
    production:
      adapter: postgresql
      encoding: utf8
      database: canvas_production
      host: canvas-postgres
      username: canvas
      password: <%= ENV['CANVAS_DB_PASSWORD'] %>
      timeout: 5000

  # Cache configuration
  cache_store.yml: |
    production:
      cache_store: redis_cache_store
      servers:
        - redis://canvas-redis:6379/0

  # Redis configuration
  redis.yml: |
    production:
      servers:
        - redis://canvas-redis:6379/1

  # Domain configuration
  domain.yml: |
    production:
      domain: "canvas.${DOMAIN}"
      ssl: true

  # Security configuration
  security.yml: |
    production:
      encryption_key: "${CANVAS_ENCRYPTION_KEY}"

  # Outgoing mail (placeholder)
  outgoing_mail.yml: |
    production:
      address: "localhost"
      port: "25"
      domain: "${DOMAIN}"
      authentication: "plain"

  # Dynamic settings
  dynamic_settings.yml: |
    production:
      config:
        canvas:
          canvas:
            encryption-secret: "${CANVAS_ENCRYPTION_KEY}"
            signing-secret: "${CANVAS_SIGNING_KEY}"
```

**Step 2: Commit**

```bash
git add components/canvas/canvas-config.yaml
git commit -m "feat(canvas): add configuration manifest"
```

---

## Task 8: Create Canvas Web Deployment Manifest

**Files:**
- Create: `components/canvas/canvas-web.yaml`

**Step 1: Create Canvas web deployment**

Create `components/canvas/canvas-web.yaml`:
```yaml
# Canvas LMS Web Application
apiVersion: apps/v1
kind: Deployment
metadata:
  name: canvas-web
  namespace: canvas
spec:
  replicas: 1
  selector:
    matchLabels:
      app: canvas-web
  template:
    metadata:
      labels:
        app: canvas-web
    spec:
      initContainers:
      # Wait for PostgreSQL
      - name: wait-for-postgres
        image: postgres:12-alpine
        command: ['sh', '-c', 'until pg_isready -h canvas-postgres -U canvas; do echo waiting for postgres; sleep 2; done;']
      # Wait for Redis
      - name: wait-for-redis
        image: redis:7-alpine
        command: ['sh', '-c', 'until redis-cli -h canvas-redis ping; do echo waiting for redis; sleep 2; done;']
      containers:
      - name: canvas
        image: instructure/canvas-lms:stable
        ports:
        - containerPort: 3000
          name: http
        env:
        - name: CANVAS_LMS_ADMIN_EMAIL
          value: "admin@${DOMAIN}"
        - name: CANVAS_LMS_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: canvas-secrets
              key: admin-password
        - name: CANVAS_LMS_ACCOUNT_NAME
          value: "LTI Testing"
        - name: CANVAS_LMS_STATS_COLLECTION
          value: "opt_out"
        - name: CANVAS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: canvas-postgres-secret
              key: POSTGRES_PASSWORD
        - name: CANVAS_ENCRYPTION_KEY
          valueFrom:
            secretKeyRef:
              name: canvas-secrets
              key: encryption-key
        - name: CANVAS_SIGNING_KEY
          valueFrom:
            secretKeyRef:
              name: canvas-secrets
              key: signing-key
        - name: RAILS_ENV
          value: "production"
        - name: DOMAIN
          value: "${DOMAIN}"
        volumeMounts:
        - name: config
          mountPath: /usr/src/app/config/database.yml
          subPath: database.yml
        - name: config
          mountPath: /usr/src/app/config/cache_store.yml
          subPath: cache_store.yml
        - name: config
          mountPath: /usr/src/app/config/redis.yml
          subPath: redis.yml
        - name: config
          mountPath: /usr/src/app/config/domain.yml
          subPath: domain.yml
        - name: config
          mountPath: /usr/src/app/config/security.yml
          subPath: security.yml
        - name: config
          mountPath: /usr/src/app/config/outgoing_mail.yml
          subPath: outgoing_mail.yml
        - name: config
          mountPath: /usr/src/app/config/dynamic_settings.yml
          subPath: dynamic_settings.yml
        - name: canvas-data
          mountPath: /usr/src/app/tmp
        resources:
          requests:
            memory: "512Mi"
            cpu: "300m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        readinessProbe:
          httpGet:
            path: /health_check
            port: 3000
          initialDelaySeconds: 120
          periodSeconds: 10
          timeoutSeconds: 5
        livenessProbe:
          httpGet:
            path: /health_check
            port: 3000
          initialDelaySeconds: 180
          periodSeconds: 30
          timeoutSeconds: 10
      volumes:
      - name: config
        configMap:
          name: canvas-config
      - name: canvas-data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: canvas-web
  namespace: canvas
spec:
  selector:
    app: canvas-web
  ports:
  - port: 3000
    targetPort: 3000
```

**Step 2: Commit**

```bash
git add components/canvas/canvas-web.yaml
git commit -m "feat(canvas): add web deployment manifest"
```

---

## Task 9: Create Canvas Jobs Deployment Manifest

**Files:**
- Create: `components/canvas/canvas-jobs.yaml`

**Step 1: Create Canvas jobs (background worker) deployment**

Create `components/canvas/canvas-jobs.yaml`:
```yaml
# Canvas Background Jobs Worker
apiVersion: apps/v1
kind: Deployment
metadata:
  name: canvas-jobs
  namespace: canvas
spec:
  replicas: 1
  selector:
    matchLabels:
      app: canvas-jobs
  template:
    metadata:
      labels:
        app: canvas-jobs
    spec:
      initContainers:
      - name: wait-for-postgres
        image: postgres:12-alpine
        command: ['sh', '-c', 'until pg_isready -h canvas-postgres -U canvas; do echo waiting for postgres; sleep 2; done;']
      - name: wait-for-redis
        image: redis:7-alpine
        command: ['sh', '-c', 'until redis-cli -h canvas-redis ping; do echo waiting for redis; sleep 2; done;']
      containers:
      - name: canvas-jobs
        image: instructure/canvas-lms:stable
        command: ["bundle", "exec", "script/delayed_job", "run"]
        env:
        - name: CANVAS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: canvas-postgres-secret
              key: POSTGRES_PASSWORD
        - name: CANVAS_ENCRYPTION_KEY
          valueFrom:
            secretKeyRef:
              name: canvas-secrets
              key: encryption-key
        - name: CANVAS_SIGNING_KEY
          valueFrom:
            secretKeyRef:
              name: canvas-secrets
              key: signing-key
        - name: RAILS_ENV
          value: "production"
        - name: DOMAIN
          value: "${DOMAIN}"
        volumeMounts:
        - name: config
          mountPath: /usr/src/app/config/database.yml
          subPath: database.yml
        - name: config
          mountPath: /usr/src/app/config/cache_store.yml
          subPath: cache_store.yml
        - name: config
          mountPath: /usr/src/app/config/redis.yml
          subPath: redis.yml
        - name: config
          mountPath: /usr/src/app/config/domain.yml
          subPath: domain.yml
        - name: config
          mountPath: /usr/src/app/config/security.yml
          subPath: security.yml
        - name: config
          mountPath: /usr/src/app/config/dynamic_settings.yml
          subPath: dynamic_settings.yml
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: config
        configMap:
          name: canvas-config
```

**Step 2: Commit**

```bash
git add components/canvas/canvas-jobs.yaml
git commit -m "feat(canvas): add background jobs worker manifest"
```

---

## Task 10: Create Canvas Ingress Manifest

**Files:**
- Create: `components/canvas/canvas-ingress.yaml`

**Step 1: Create Canvas ingress**

Create `components/canvas/canvas-ingress.yaml`:
```yaml
# Canvas LMS Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: canvas-ingress
  namespace: canvas
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "500m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    # Canvas needs websocket support for some features
    nginx.ingress.kubernetes.io/websocket-services: "canvas-web"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - canvas.${DOMAIN}
    secretName: canvas-tls
  rules:
  - host: canvas.${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: canvas-web
            port:
              number: 3000
```

**Step 2: Commit**

```bash
git add components/canvas/canvas-ingress.yaml
git commit -m "feat(canvas): add ingress manifest"
```

---

## Task 11: Create Canvas Install Script

**Files:**
- Create: `components/canvas/install.sh`

**Step 1: Create the install script**

Create `components/canvas/install.sh`:
```bash
#!/bin/bash
set -euo pipefail

# Canvas LMS Installation
# Instructure Canvas for LTI integration testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Component metadata
COMPONENT_NAME="canvas"
COMPONENT_NAMESPACE="canvas"

install_canvas() {
    info "Installing Canvas LMS..."

    if [[ -z "${DOMAIN:-}" ]]; then
        error "DOMAIN is required for Canvas installation"
    fi

    # Create namespace
    kubectl create namespace ${COMPONENT_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    # Generate secrets
    CANVAS_ADMIN_PASSWORD=$(generate_password)
    CANVAS_DB_PASSWORD=$(generate_password)
    CANVAS_ENCRYPTION_KEY=$(openssl rand -hex 32)
    CANVAS_SIGNING_KEY=$(openssl rand -hex 32)

    # Save credentials
    mkdir -p "${SCRIPT_DIR}/../../.cluster/credentials"
    cat > "${SCRIPT_DIR}/../../.cluster/credentials/canvas.conf" <<EOF
CANVAS_URL=https://canvas.${DOMAIN}
ADMIN_EMAIL=admin@${DOMAIN}
ADMIN_PASSWORD=${CANVAS_ADMIN_PASSWORD}
DB_PASSWORD=${CANVAS_DB_PASSWORD}
ENCRYPTION_KEY=${CANVAS_ENCRYPTION_KEY}
SIGNING_KEY=${CANVAS_SIGNING_KEY}

# LTI 1.3 Configuration
# After installation, configure LTI Developer Keys at:
# Admin → Developer Keys → + Developer Key → + LTI Key

# Authentik SSO (manual configuration required)
# 1. Create OIDC provider in Authentik for 'Canvas LMS'
# 2. In Canvas: Admin → Authentication → + Provider → OpenID Connect
# 3. Configure with Authentik endpoints
EOF
    chmod 600 "${SCRIPT_DIR}/../../.cluster/credentials/canvas.conf"

    # Create canvas secrets
    info "Creating Canvas secrets..."
    kubectl create secret generic canvas-secrets \
        --namespace=${COMPONENT_NAMESPACE} \
        --from-literal=admin-password="${CANVAS_ADMIN_PASSWORD}" \
        --from-literal=encryption-key="${CANVAS_ENCRYPTION_KEY}" \
        --from-literal=signing-key="${CANVAS_SIGNING_KEY}" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Export for envsubst
    export DOMAIN
    export CANVAS_DB_PASSWORD
    export CANVAS_ENCRYPTION_KEY
    export CANVAS_SIGNING_KEY

    # Deploy PostgreSQL
    info "Deploying PostgreSQL for Canvas..."
    envsubst < "${SCRIPT_DIR}/canvas-postgres.yaml" | kubectl apply -f -

    # Deploy Redis
    info "Deploying Redis..."
    kubectl apply -f "${SCRIPT_DIR}/canvas-redis.yaml"

    # Wait for dependencies
    info "Waiting for PostgreSQL..."
    kubectl wait --for=condition=ready pod -l app=canvas-postgres -n ${COMPONENT_NAMESPACE} --timeout=300s

    info "Waiting for Redis..."
    kubectl wait --for=condition=ready pod -l app=canvas-redis -n ${COMPONENT_NAMESPACE} --timeout=120s

    # Deploy Canvas configuration
    info "Deploying Canvas configuration..."
    envsubst < "${SCRIPT_DIR}/canvas-config.yaml" | kubectl apply -f -

    # Deploy Canvas web
    info "Deploying Canvas web application..."
    envsubst < "${SCRIPT_DIR}/canvas-web.yaml" | kubectl apply -f -

    # Deploy Canvas jobs worker
    info "Deploying Canvas background jobs..."
    envsubst < "${SCRIPT_DIR}/canvas-jobs.yaml" | kubectl apply -f -

    # Deploy ingress
    info "Deploying Canvas ingress..."
    envsubst < "${SCRIPT_DIR}/canvas-ingress.yaml" | kubectl apply -f -

    # Wait for deployment (Canvas takes a while to start)
    info "Waiting for Canvas deployment (this may take several minutes)..."
    kubectl rollout status deployment/canvas-web -n ${COMPONENT_NAMESPACE} --timeout=900s || {
        warn "Canvas web deployment is taking longer than expected."
        warn "Check logs with: kubectl logs -n canvas -l app=canvas-web"
    }

    success "Canvas installed successfully!"
    info ""
    info "=== Canvas Access Information ==="
    info "URL: https://canvas.${DOMAIN}"
    info "Admin Email: admin@${DOMAIN}"
    info "Admin Password: See .cluster/credentials/canvas.conf"
    info ""
    info "NOTE: Canvas may take several minutes to fully initialize on first boot."
    info "      Check status with: kubectl get pods -n canvas"
    info ""
    info "=== LTI 1.3 Setup ==="
    info "1. Login as admin"
    info "2. Admin → Developer Keys"
    info "3. + Developer Key → + LTI Key"
    info "4. Configure your tool and enable the key"
    info ""
    info "=== Authentik SSO Setup (optional) ==="
    info "1. Create OIDC provider in Authentik for 'Canvas LMS'"
    info "2. In Canvas: Admin → Authentication → + Provider"
    info "3. Select OpenID Connect"
    info "4. Configure with Authentik endpoints"
}

uninstall_canvas() {
    info "Uninstalling Canvas..."

    kubectl delete namespace ${COMPONENT_NAMESPACE} --ignore-not-found --timeout=120s || {
        warn "Namespace deletion timed out. Forcing..."
        kubectl delete namespace ${COMPONENT_NAMESPACE} --force --grace-period=0 || true
    }

    success "Canvas uninstalled!"
}

# Main execution
case "${1:-install}" in
    install)
        install_canvas
        ;;
    uninstall)
        uninstall_canvas
        ;;
    *)
        error "Usage: $0 [install|uninstall]"
        ;;
esac
```

**Step 2: Make the script executable**

```bash
chmod +x components/canvas/install.sh
```

**Step 3: Commit**

```bash
git add components/canvas/install.sh
git commit -m "feat(canvas): add installation script"
```

---

## Task 12: Test Moodle Deployment

**Step 1: Set environment and deploy Moodle**

```bash
export KUBECONFIG=~/.kube/config-hetzner
export DOMAIN=gmac.io
./components/moodle/install.sh
```

**Step 2: Verify Moodle pods are running**

```bash
kubectl get pods -n moodle
```

Expected: All pods in Running state (may take 5-10 minutes for initial setup)

**Step 3: Verify ingress and certificate**

```bash
kubectl get ingress -n moodle
kubectl get certificate -n moodle
```

Expected: Ingress created, certificate Ready=True

**Step 4: Test Moodle access**

```bash
curl -I https://moodle.gmac.io
```

Expected: HTTP 200 or 302 redirect to login

**Step 5: Commit verification notes**

No commit needed - deployment verification complete.

---

## Task 13: Test Canvas Deployment

**Step 1: Deploy Canvas**

```bash
export KUBECONFIG=~/.kube/config-hetzner
export DOMAIN=gmac.io
./components/canvas/install.sh
```

**Step 2: Verify Canvas pods are running**

```bash
kubectl get pods -n canvas
```

Expected: All pods in Running state (may take 10-15 minutes for Canvas)

**Step 3: Check Canvas logs if needed**

```bash
kubectl logs -n canvas -l app=canvas-web --tail=50
```

**Step 4: Verify ingress and certificate**

```bash
kubectl get ingress -n canvas
kubectl get certificate -n canvas
```

**Step 5: Test Canvas access**

```bash
curl -I https://canvas.gmac.io
```

Expected: HTTP 200 or 302 redirect

---

## Task 14: Final Commit and Documentation Update

**Step 1: Update main README or component list if exists**

Check if there's a components list to update:
```bash
ls -la components/README.md 2>/dev/null || echo "No components README"
```

**Step 2: Create final commit with all changes**

```bash
git add -A
git status
git commit -m "feat: add Canvas and Moodle LMS for LTI testing

- Moodle: Bitnami Helm chart with PostgreSQL, minimal resources
- Canvas: Instructure images with PostgreSQL, Redis, jobs worker
- Both configured for LTI 1.3 + Advantage support
- Ready for Authentik SSO integration

Accessible at:
- https://canvas.gmac.io
- https://moodle.gmac.io"
```

---

## Post-Implementation: Manual Configuration

After deployment, complete these manual steps:

### Authentik SSO Setup (for both LMS)

1. Login to `https://auth.gmac.io` as admin
2. Applications → Create → name: "Canvas LMS" / "Moodle LMS"
3. For each, create an OAuth2/OpenID Provider:
   - Client type: Confidential
   - Redirect URIs: `https://canvas.gmac.io/login/oauth2/callback` / `https://moodle.gmac.io/admin/oauth2callback.php`
4. Note the Client ID and Client Secret

### Canvas LTI 1.3 Setup

1. Login to `https://canvas.gmac.io` as admin
2. Admin → Developer Keys → + Developer Key → + LTI Key
3. Configure with your education software's LTI details
4. Enable the key

### Moodle LTI 1.3 Setup

1. Login to `https://moodle.gmac.io` as admin
2. Site Administration → Plugins → Activity modules → External tool
3. Manage tools → Configure a tool manually
4. Enter LTI 1.3 configuration details
