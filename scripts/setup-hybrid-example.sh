#!/bin/bash
# Example: Setup hybrid infrastructure with existing Gitea VPS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

info "Setting up hybrid infrastructure example..."

# Check if Gitea VPS is already registered
if [[ -f "${SCRIPT_DIR}/../.cluster/vps-inventory.json" ]] && \
   jq -e '.vps_instances[] | select(.name == "gitea")' "${SCRIPT_DIR}/../.cluster/vps-inventory.json" >/dev/null 2>&1; then
    info "Gitea VPS already registered"
else
    info "Registering existing Gitea VPS..."
    
    # Add the existing Gitea VPS at ci.gmac.io
    "${SCRIPT_DIR}/vps-manage.sh" add gitea \
        --ip 5.78.92.8 \
        --domain ci.gmac.io \
        --services gitea,postgres,nginx \
        --provider hetzner
fi

# Show current infrastructure
info "=== Current Infrastructure ==="
echo ""
info "K3s Cluster Nodes:"
kubectl get nodes -o wide 2>/dev/null || echo "  Cluster not deployed yet"

echo ""
info "Managed VPS Instances:"
"${SCRIPT_DIR}/vps-manage.sh" list

echo ""
info "=== Next Steps ==="
echo "1. Deploy K3s cluster: ./bootstrap.sh --environment hetzner --components all"
echo "2. Access control panel: https://<your-domain>"
echo "3. Monitor Gitea VPS: ./scripts/vps-manage.sh monitor gitea"
echo "4. Setup unified backups for both cluster and VPS"
echo ""
info "The control panel will provide a unified view of:"
echo "  - K3s cluster resources and scaling"
echo "  - Gitea VPS health and metrics"
echo "  - Integrated monitoring and alerting"
echo "  - Backup status for all infrastructure"