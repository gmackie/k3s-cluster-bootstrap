#!/bin/bash
# Check monitoring stack health

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Check component health
check_prometheus() {
    info "Checking Prometheus..."
    
    # Check if Prometheus pods are running
    local prometheus_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o json)
    local running_count=$(echo "$prometheus_pods" | jq '[.items[] | select(.status.phase=="Running")] | length')
    local total_count=$(echo "$prometheus_pods" | jq '.items | length')
    
    if [[ $running_count -eq $total_count && $total_count -gt 0 ]]; then
        success "Prometheus: $running_count/$total_count pods running"
        
        # Check Prometheus targets
        local prometheus_url="http://prometheus-kube-prometheus-prometheus.monitoring:9090"
        local targets=$(kubectl exec -n monitoring deployment/prometheus-kube-prometheus-operator -- \
            curl -s "$prometheus_url/api/v1/targets" 2>/dev/null || echo '{"data":{"activeTargets":[]}}')
        
        local active_targets=$(echo "$targets" | jq '.data.activeTargets | length' 2>/dev/null || echo 0)
        info "  Active targets: $active_targets"
    else
        error "Prometheus: Only $running_count/$total_count pods running"
    fi
}

check_grafana() {
    info "Checking Grafana..."
    
    local grafana_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o json)
    local running_count=$(echo "$grafana_pods" | jq '[.items[] | select(.status.phase=="Running")] | length')
    local total_count=$(echo "$grafana_pods" | jq '.items | length')
    
    if [[ $running_count -eq $total_count && $total_count -gt 0 ]]; then
        success "Grafana: $running_count/$total_count pods running"
        
        # Check data sources
        info "  Checking data sources..."
        kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- \
            curl -s http://localhost:3000/api/datasources \
            -H "Authorization: Bearer $(kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)" \
            2>/dev/null | jq -r '.[] | "  - \(.name): \(.type)"' || echo "  Unable to check data sources"
    else
        error "Grafana: Only $running_count/$total_count pods running"
    fi
}

check_loki() {
    info "Checking Loki..."
    
    local loki_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=loki -o json)
    local running_count=$(echo "$loki_pods" | jq '[.items[] | select(.status.phase=="Running")] | length')
    local total_count=$(echo "$loki_pods" | jq '.items | length')
    
    if [[ $running_count -eq $total_count && $total_count -gt 0 ]]; then
        success "Loki: $running_count/$total_count pods running"
        
        # Check Loki ingestion rate
        local loki_metrics=$(kubectl exec -n monitoring -l app.kubernetes.io/name=loki -- \
            curl -s http://localhost:3100/metrics 2>/dev/null | grep "loki_distributor_bytes_received_total" | tail -1 || echo "")
        
        if [[ -n "$loki_metrics" ]]; then
            info "  Log ingestion is active"
        fi
    else
        error "Loki: Only $running_count/$total_count pods running"
    fi
}

check_promtail() {
    info "Checking Promtail..."
    
    local promtail_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail -o json)
    local running_count=$(echo "$promtail_pods" | jq '[.items[] | select(.status.phase=="Running")] | length')
    local total_count=$(echo "$promtail_pods" | jq '.items | length')
    local node_count=$(kubectl get nodes --no-headers | wc -l)
    
    if [[ $running_count -eq $node_count ]]; then
        success "Promtail: $running_count/$node_count agents running (one per node)"
    else
        warn "Promtail: Only $running_count/$node_count agents running"
    fi
}

check_alertmanager() {
    info "Checking Alertmanager..."
    
    local am_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager -o json)
    local running_count=$(echo "$am_pods" | jq '[.items[] | select(.status.phase=="Running")] | length')
    local total_count=$(echo "$am_pods" | jq '.items | length')
    
    if [[ $running_count -eq $total_count && $total_count -gt 0 ]]; then
        success "Alertmanager: $running_count/$total_count pods running"
        
        # Check active alerts
        local alerts=$(kubectl exec -n monitoring statefulset/alertmanager-kube-prometheus-alertmanager -- \
            curl -s http://localhost:9093/api/v1/alerts 2>/dev/null || echo '[]')
        
        local active_alerts=$(echo "$alerts" | jq 'length' 2>/dev/null || echo 0)
        info "  Active alerts: $active_alerts"
    else
        error "Alertmanager: Only $running_count/$total_count pods running"
    fi
}

check_metrics_server() {
    info "Checking metrics-server..."
    
    if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
        local ready=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}')
        local desired=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.spec.replicas}')
        
        if [[ "$ready" == "$desired" ]]; then
            success "Metrics Server: $ready/$desired replicas ready"
            
            # Test metrics
            if kubectl top nodes >/dev/null 2>&1; then
                info "  Node metrics available"
            else
                warn "  Node metrics not available"
            fi
        else
            error "Metrics Server: Only $ready/$desired replicas ready"
        fi
    else
        warn "Metrics Server not installed (required for kubectl top and HPA)"
    fi
}

# Check storage usage
check_storage() {
    info "Checking monitoring storage usage..."
    
    local pvcs=$(kubectl get pvc -n monitoring -o json)
    echo "$pvcs" | jq -r '.items[] | "\(.metadata.name): \(.status.capacity.storage // "pending")"' | while read line; do
        info "  $line"
    done
}

# Main health check
info "=== Monitoring Stack Health Check ==="
echo ""

check_prometheus
echo ""

check_grafana
echo ""

check_loki
echo ""

check_promtail
echo ""

check_alertmanager
echo ""

check_metrics_server
echo ""

check_storage
echo ""

# Summary
info "=== Summary ==="

# Check if all components are healthy
if kubectl get pods -n monitoring -o json | jq -e '.items[] | select(.status.phase!="Running")' >/dev/null 2>&1; then
    warn "Some monitoring components are not healthy"
    kubectl get pods -n monitoring | grep -v Running || true
else
    success "All monitoring components are healthy"
fi

# Show access URLs
echo ""
info "=== Access URLs ==="
info "Grafana: https://${DOMAIN:-localhost}/grafana"
info "Prometheus: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
info "Alertmanager: kubectl port-forward -n monitoring svc/alertmanager-kube-prometheus-alertmanager 9093:9093"
info "Loki: kubectl port-forward -n monitoring svc/loki-gateway 3100:80"