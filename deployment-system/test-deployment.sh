#!/bin/bash
set -euo pipefail

echo "=== Testing Auto-Deployment System ==="

# Test repo name
TEST_REPO="test-auto-deploy-$(date +%s)"
TEST_DOMAIN="test-deploy.gmac.io"

# Create a test repository
echo "Creating test repository: $TEST_REPO"
ssh root@ci.gmac.io "su git -c 'cd /var/lib/gitea/repositories/gmackie && git init --bare ${TEST_REPO}.git'"

# Clone and add test app
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

git clone https://git.gmac.io/gmackie/${TEST_REPO}.git
cd ${TEST_REPO}

# Create a simple Node.js app
cat > package.json << 'EOF'
{
  "name": "test-auto-deploy",
  "version": "1.0.0",
  "scripts": {
    "start": "node server.js"
  }
}
EOF

cat > server.js << 'EOF'
const http = require('http');
const port = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({ status: 'healthy', time: new Date() }));
  } else {
    res.writeHead(200, {'Content-Type': 'text/html'});
    res.end(`
      <h1>Auto-Deploy Test Success!</h1>
      <p>Deployed at: ${new Date()}</p>
      <p>Running on port: ${port}</p>
    `);
  }
});

server.listen(port, () => {
  console.log(`Test server running on port ${port}`);
});
EOF

# Commit and push
git add .
git commit -m "Initial test app"
git push -u origin main || git push -u origin master

# Run deployment
echo ""
echo "Running deployment..."
bash /tmp/deploy-app.sh ${TEST_REPO} ${TEST_DOMAIN} 3000

# Create ArgoCD app manually if needed
cat > /tmp/test-argocd-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${TEST_REPO}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://git.gmac.io/gmackie/${TEST_REPO}
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: ${TEST_REPO}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

KUBECONFIG=/Users/mackieg/.kube/config-hetzner kubectl apply -f /tmp/test-argocd-app.yaml

echo ""
echo "=== Test deployment initiated ==="
echo "Repository: https://git.gmac.io/gmackie/${TEST_REPO}"
echo "Application: https://${TEST_DOMAIN} (available in ~3 minutes)"
echo ""
echo "Check status with:"
echo "  kubectl get pods -n ${TEST_REPO}"
echo "  kubectl get ingress -n ${TEST_REPO}"
echo ""
echo "Clean up test with:"
echo "  kubectl delete application -n argocd ${TEST_REPO}"
echo "  kubectl delete namespace ${TEST_REPO}"

cd /
rm -rf $TEMP_DIR