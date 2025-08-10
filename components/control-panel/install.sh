#!/bin/bash
# Control Panel installation

source "${SCRIPT_DIR}/lib/common.sh"

info "Installing Control Panel..."

# Create namespace
ensure_namespace control-panel

# Check if control-panel directory exists
if [[ ! -d "${SCRIPT_DIR}/control-panel" ]]; then
    warn "Control panel source code not found at ${SCRIPT_DIR}/control-panel"
    warn "Please ensure the control-panel application is present"
    return 1
fi

# Build control panel image (if running locally)
if [[ "$ENVIRONMENT" == "local" ]]; then
    info "Building control panel Docker image..."
    
    cd "${SCRIPT_DIR}/control-panel"
    
    # Create Dockerfile if it doesn't exist
    if [[ ! -f Dockerfile ]]; then
        cat > Dockerfile <<'EOF'
# Multi-stage build for control panel
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Production image
FROM node:18-alpine

WORKDIR /app

# Copy built application
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package*.json ./

# Install production dependencies only
RUN npm ci --production

# Expose port
EXPOSE 3000

# Start the application
CMD ["npm", "start"]
EOF
    fi
    
    # Build and push to local registry (if available)
    docker build -t control-panel:latest .
    
    # For k3s, we can import the image directly
    docker save control-panel:latest | sudo k3s ctr images import -
    
    cd "${SCRIPT_DIR}"
fi

# Generate dashboard configuration
info "Generating control panel dashboard..."
if [[ -f "${SCRIPT_DIR}/components/control-panel/generate-config.sh" ]]; then
    bash "${SCRIPT_DIR}/components/control-panel/generate-config.sh"
else
    warn "Dashboard generator not found, creating default dashboard"
    # Create default dashboard
    cat > "${SCRIPT_DIR}/components/control-panel/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>K3s Cluster Control Panel</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0e27;
            color: #e4e8ee;
            margin: 0;
            padding: 20px;
            text-align: center;
        }
        h1 { color: #667eea; }
        p { color: #8892b0; }
    </style>
</head>
<body>
    <h1>K3s Cluster Control Panel</h1>
    <p>Services are being discovered...</p>
</body>
</html>
EOF
fi

# Create ConfigMap with dashboard
kubectl create configmap control-panel-dashboard \
    --namespace=control-panel \
    --from-file=index.html="${SCRIPT_DIR}/components/control-panel/index.html" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create ConfigMap for control panel configuration
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: control-panel-config
  namespace: control-panel
data:
  config.json: |
    {
      "api": {
        "kubernetes": {
          "inCluster": true
        }
      },
      "features": {
        "monitoring": true,
        "deployments": true,
        "gitea": true,
        "logs": true,
        "metrics": true,
        "clusterScaling": true,
        "nodeManagement": true,
        "vpsManagement": true,
        "hybridInfrastructure": true
      },
      "services": {
        "prometheus": "http://prometheus-kube-prometheus-prometheus.monitoring:9090",
        "grafana": "/grafana",
        "gitea": "/git",
        "alertmanager": "http://alertmanager-kube-prometheus-alertmanager.monitoring:9093"
      },
      "scaling": {
        "enabled": true,
        "provider": "${PROVIDER:-hetzner}",
        "thresholds": {
          "cpuScaleUp": 80,
          "cpuScaleDown": 20,
          "memScaleUp": 80,
          "memScaleDown": 20
        },
        "limits": {
          "minNodes": 1,
          "maxNodes": 10
        },
        "cooldown": {
          "scaleUp": 300,
          "scaleDown": 600
        }
      },
      "vps": {
        "enabled": true,
        "inventoryPath": "/app/data/vps-inventory.json",
        "monitoring": {
          "enabled": true,
          "interval": 300
        },
        "gitea": {
          "url": "${GITEA_URL:-https://ci.gmac.io}",
          "managed": true
        }
      }
    }
EOF

# Create RBAC for control panel
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: control-panel
  namespace: control-panel
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: control-panel
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "endpoints", "persistentvolumeclaims", "events", "configmaps", "secrets", "namespaces", "nodes"]
    verbs: ["*"]
  - apiGroups: ["apps"]
    resources: ["deployments", "daemonsets", "replicasets", "statefulsets"]
    verbs: ["*"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["*"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["pods/log", "pods/exec", "pods/portforward"]
    verbs: ["get", "list", "create"]
  - apiGroups: ["metrics.k8s.io"]
    resources: ["pods", "nodes"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: control-panel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: control-panel
subjects:
  - kind: ServiceAccount
    name: control-panel
    namespace: control-panel
EOF

# Create ConfigMap with cluster management scripts
info "Creating cluster management scripts ConfigMap..."
kubectl create configmap control-panel-scripts \
  --from-file="${SCRIPT_DIR}/scripts/cluster-scale.sh" \
  --from-file="${SCRIPT_DIR}/scripts/cluster-monitor.sh" \
  --from-file="${SCRIPT_DIR}/scripts/node-add.sh" \
  --from-file="${SCRIPT_DIR}/scripts/node-remove.sh" \
  --from-file="${SCRIPT_DIR}/scripts/vps-manage.sh" \
  -n control-panel \
  --dry-run=client -o yaml | kubectl apply -f -

# Mount VPS inventory
kubectl create configmap vps-inventory \
  --from-file="${SCRIPT_DIR}/.cluster/vps-inventory.json" \
  -n control-panel \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

# Create PVC for VPS data
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: control-panel-vps-data
  namespace: control-panel
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: ${STORAGE_CLASS:-local-path}
EOF

# Deploy control panel
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: control-panel
  namespace: control-panel
  labels:
    app: control-panel
spec:
  replicas: 1
  selector:
    matchLabels:
      app: control-panel
  template:
    metadata:
      labels:
        app: control-panel
    spec:
      serviceAccountName: control-panel
      containers:
      - name: control-panel
        image: ${CONTROL_PANEL_IMAGE:-control-panel:latest}
        imagePullPolicy: ${IMAGE_PULL_POLICY:-IfNotPresent}
        ports:
        - containerPort: 3000
          name: http
        env:
        - name: NODE_ENV
          value: production
        - name: PORT
          value: "3000"
        volumeMounts:
        - name: config
          mountPath: /app/config
          readOnly: true
        - name: cluster-scripts
          mountPath: /app/scripts
          readOnly: true
        - name: vps-data
          mountPath: /app/data
        - name: dashboard
          mountPath: /app/public
          readOnly: true
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: control-panel-config
      - name: cluster-scripts
        configMap:
          name: control-panel-scripts
          defaultMode: 0755
      - name: vps-data
        persistentVolumeClaim:
          claimName: control-panel-vps-data
      - name: dashboard
        configMap:
          name: control-panel-dashboard
---
apiVersion: v1
kind: Service
metadata:
  name: control-panel
  namespace: control-panel
  labels:
    app: control-panel
spec:
  selector:
    app: control-panel
  ports:
  - port: 80
    targetPort: http
    protocol: TCP
    name: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: control-panel
  namespace: control-panel
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - ${DOMAIN:-control-panel.local}
    secretName: control-panel-tls
  rules:
  - host: ${DOMAIN:-control-panel.local}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: control-panel
            port:
              name: http
EOF

# Wait for deployment to be ready
wait_for_deployment control-panel control-panel

# Create network policies for security
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: control-panel-network-policy
  namespace: control-panel
spec:
  podSelector:
    matchLabels:
      app: control-panel
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 3000
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 80
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 6443
  - to:
    - namespaceSelector:
        matchLabels:
          name: monitoring
  - to:
    - namespaceSelector:
        matchLabels:
          name: gitea
EOF

success "Control Panel installed successfully"
info "Access Control Panel at: https://${DOMAIN:-control-panel.local}"
info "The control panel provides:"
info "  - Cluster overview and management"
info "  - Application deployments"
info "  - Monitoring integration"
info "  - Log viewing"
info "  - Gitea integration"