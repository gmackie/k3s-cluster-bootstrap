#!/bin/bash

# Deploy monitoring stack to k3s cluster

set -e

echo "=== Deploying Monitoring Stack to k3s cluster ==="

# Check if kubeconfig exists
if [ ! -f ~/kube-conf.yaml ]; then
    echo "Error: ~/kube-conf.yaml not found"
    exit 1
fi

export KUBECONFIG=~/kube-conf.yaml

# Apply all manifests in order
echo "Creating monitoring namespace..."
kubectl apply -f k8s/00-namespace.yaml

echo "Creating ConfigMaps and Secrets..."
kubectl apply -f k8s/01-oauth2-proxy-config.yaml
kubectl apply -f k8s/02-secrets.yaml

echo "Deploying OAuth2 Proxy..."
kubectl apply -f k8s/03-oauth2-proxy.yaml

echo "Deploying Prometheus..."
kubectl apply -f k8s/04-prometheus.yaml

echo "Deploying Grafana..."
kubectl apply -f k8s/05-grafana.yaml

echo "Deploying Alertmanager..."
kubectl apply -f k8s/06-alertmanager.yaml

echo "Creating Ingress rules..."
kubectl apply -f k8s/07-ingress.yaml

echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=oauth2-proxy -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=alertmanager -n monitoring --timeout=300s

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Monitoring services will be available at:"
echo "  - https://monitoring.gmac.io (Prometheus)"
echo "  - https://metrics.gmac.io (Grafana)"
echo "  - https://alerts.gmac.io (Alertmanager)"
echo ""
echo "All services use single sign-on with GitHub OAuth."
echo "Cookie is shared across all *.gmac.io domains."
echo ""
echo "Grafana admin credentials:"
echo "  Username: admin"
echo "  Password: Ui6UcgiTDq7wipgA"
echo ""
echo "To check status:"
echo "  kubectl get pods -n monitoring"
echo "  kubectl get ingress -n monitoring"