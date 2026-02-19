#!/bin/bash
# Quick cluster status check

export KUBECONFIG=~/.kube/config-hetzner

echo "=== Cluster Status ==="
echo "Current context: $(kubectl config current-context)"
echo ""

echo "=== Nodes ==="
kubectl get nodes
echo ""

echo "=== Namespaces ==="
kubectl get namespaces
echo ""

echo "=== Installed Components ==="
echo -n "✓ K3s Base: "; kubectl get ns kube-system >/dev/null 2>&1 && echo "Installed" || echo "Not found"
echo -n "✓ Ingress Controller: "; kubectl get ns ingress-nginx >/dev/null 2>&1 && echo "Installed" || echo "Not found"
echo -n "✓ Cert Manager: "; kubectl get ns cert-manager >/dev/null 2>&1 && echo "Installed" || echo "Not found"
echo -n "✓ Longhorn Storage: "; kubectl get ns longhorn-system >/dev/null 2>&1 && echo "Installed" || echo "Not found"
echo -n "✓ OAuth2 Auth: "; kubectl get ns auth-system >/dev/null 2>&1 && echo "Installed" || echo "Not found"
echo -n "✓ Monitoring Stack: "; kubectl get ns monitoring >/dev/null 2>&1 && echo "Installed" || echo "Not found"
echo -n "✓ ArgoCD: "; kubectl get ns argocd >/dev/null 2>&1 && echo "Installed" || echo "Not found"
echo -n "✓ K8s Dashboard: "; kubectl get ns kubernetes-dashboard >/dev/null 2>&1 && echo "Installed" || echo "Not found"
echo -n "✓ Control Panel: "; kubectl get ns control-panel >/dev/null 2>&1 && echo "Installed" || echo "Not found"
echo -n "✓ Gitea: "; kubectl get ns gitea >/dev/null 2>&1 && echo "Installed" || echo "Not found"
echo -n "✓ Harbor Registry: "; kubectl get ns registry >/dev/null 2>&1 && echo "Installed" || echo "Not found"
echo ""

echo "=== Services with Ingress ==="
kubectl get ingress -A --no-headers | awk '{print "- https://"$4" ("$1"/"$2")"}'
echo ""

echo "=== Resource Usage ==="
kubectl top nodes 2>/dev/null || echo "Metrics server not available"
echo ""

echo "=== Failing Pods ==="
kubectl get pods -A | grep -v Running | grep -v Completed | grep -v NAMESPACE || echo "No failing pods found"