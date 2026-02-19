#!/bin/bash
set -euo pipefail

print_header "Installing GMAC.IO Control Panel (Full Version)"

# Configuration
NAMESPACE="control-panel"
DOMAIN="${DOMAIN:-control.gmac.io}"
REGISTRY="${REGISTRY:-ghcr.io/gmac-io}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
STORAGE_CLASS="${STORAGE_CLASS:-longhorn}"
ENABLE_AI_SERVICES="${ENABLE_AI_SERVICES:-false}"

print_info "Creating namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create backend deployment
print_info "Deploying control panel backend..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: control-panel-backend
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: control-panel-backend
  template:
    metadata:
      labels:
        app: control-panel-backend
    spec:
      containers:
      - name: backend
        image: $REGISTRY/control-panel-backend:$IMAGE_TAG
        imagePullPolicy: Always
        ports:
        - containerPort: 8000
        env:
        - name: KUBERNETES_NAMESPACE
          value: "$NAMESPACE"
        - name: DATABASE_URL
          value: "postgresql://controlpanel:controlpanel@postgresql:5432/controlpanel"
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
        livenessProbe:
          httpGet:
            path: /api/health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/health
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: control-panel-backend
  namespace: $NAMESPACE
spec:
  selector:
    app: control-panel-backend
  ports:
  - port: 8000
    targetPort: 8000
EOF

# Create frontend deployment
print_info "Deploying control panel frontend..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: control-panel-frontend
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: control-panel-frontend
  template:
    metadata:
      labels:
        app: control-panel-frontend
    spec:
      containers:
      - name: frontend
        image: $REGISTRY/control-panel:$IMAGE_TAG
        imagePullPolicy: Always
        ports:
        - containerPort: 3000
        env:
        - name: NEXT_PUBLIC_API_URL
          value: "https://$DOMAIN/api"
        - name: API_URL
          value: "http://control-panel-backend:8000"
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: control-panel-frontend
  namespace: $NAMESPACE
spec:
  selector:
    app: control-panel-frontend
  ports:
  - port: 3000
    targetPort: 3000
EOF

# Create ingress
print_info "Configuring ingress..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: control-panel
  namespace: $NAMESPACE
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.auth-system.svc.cluster.local:4180/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://gmac.io/oauth2/start?rd=\$scheme://\$host\$escaped_request_uri"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Access-Token"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - $DOMAIN
    secretName: control-panel-tls
  rules:
  - host: $DOMAIN
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: control-panel-backend
            port:
              number: 8000
      - path: /
        pathType: Prefix
        backend:
          service:
            name: control-panel-frontend
            port:
              number: 3000
EOF

# Deploy AI services if enabled
if [[ "$ENABLE_AI_SERVICES" == "true" ]]; then
    print_info "Deploying AI services..."
    
    for service in incident-prediction capacity-planning root-cause-analysis resource-optimization anomaly-detection; do
        cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: control-panel-$service
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: control-panel-$service
  template:
    metadata:
      labels:
        app: control-panel-$service
    spec:
      containers:
      - name: $service
        image: $REGISTRY/control-panel-$service:$IMAGE_TAG
        imagePullPolicy: Always
        ports:
        - containerPort: 8001
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 1000m
            memory: 2Gi
---
apiVersion: v1
kind: Service
metadata:
  name: control-panel-$service
  namespace: $NAMESPACE
spec:
  selector:
    app: control-panel-$service
  ports:
  - port: 8001
    targetPort: 8001
EOF
    done
fi

print_success "Control Panel installation complete!"
print_info "Access the control panel at: https://$DOMAIN"