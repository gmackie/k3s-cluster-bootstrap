#!/bin/bash
set -euo pipefail

export KUBECONFIG=~/.kube/config-hetzner

# NPM Registry CI credentials
NPM_REGISTRY="https://npm.gmac.io"
NPM_USERNAME="ci-build"
NPM_PASSWORD="WE05dmseLgMTy2qa"
NPM_EMAIL="ci@gmac.io"
NPM_TOKEN=$(echo -n "${NPM_USERNAME}:${NPM_PASSWORD}" | base64)

echo "Creating sealed secret for NPM registry CI credentials..."

# Create the secret in different namespaces
for NAMESPACE in default argocd gitea; do
    echo "Creating sealed secret for namespace: $NAMESPACE"
    
    # Create regular secret YAML
    kubectl create secret generic npm-registry-ci \
      --namespace=$NAMESPACE \
      --from-literal=NPM_REGISTRY="$NPM_REGISTRY" \
      --from-literal=NPM_USERNAME="$NPM_USERNAME" \
      --from-literal=NPM_PASSWORD="$NPM_PASSWORD" \
      --from-literal=NPM_EMAIL="$NPM_EMAIL" \
      --from-literal=NPM_TOKEN="$NPM_TOKEN" \
      --from-literal=NPMRC="//npm.gmac.io/:_authToken=$NPM_TOKEN" \
      --dry-run=client -o yaml > /tmp/npm-secret-$NAMESPACE.yaml
    
    # Seal the secret
    kubeseal --cert .cluster/sealed-secrets-public.pem \
      < /tmp/npm-secret-$NAMESPACE.yaml \
      > sealed-secrets/npm-registry-ci-$NAMESPACE.yaml
    
    # Apply the sealed secret
    kubectl apply -f sealed-secrets/npm-registry-ci-$NAMESPACE.yaml
    
    # Clean up temp file
    rm -f /tmp/npm-secret-$NAMESPACE.yaml
done

echo ""
echo "Sealed secrets created and applied!"
echo ""
echo "For GitHub Actions, add these secrets to your repository:"
echo "  NPM_REGISTRY: $NPM_REGISTRY"
echo "  NPM_TOKEN: $NPM_TOKEN"
echo ""
echo "In your GitHub workflow, use:"
echo '  - name: Configure NPM'
echo '    run: |'
echo '      echo "//${NPM_REGISTRY#https://}:_authToken=${NPM_TOKEN}" > ~/.npmrc'
echo '      npm config set @yourscope:registry $NPM_REGISTRY'
echo ""
echo "For ArgoCD or Kubernetes deployments, the secret is available as:"
echo "  kubectl get secret npm-registry-ci -n <namespace>"