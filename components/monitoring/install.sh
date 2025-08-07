#!/bin/bash
# Complete monitoring stack installation (Prometheus, Grafana, Loki, Alertmanager)

source "${SCRIPT_DIR}/lib/common.sh"

info "Installing complete observability stack..."

# Create namespace
ensure_namespace monitoring

# Generate passwords
GRAFANA_ADMIN_PASSWORD=$(generate_password)

# Save credentials
mkdir -p "${SCRIPT_DIR}/.cluster/credentials"
cat > "${SCRIPT_DIR}/.cluster/credentials/monitoring.conf" <<EOF
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD
EOF
chmod 600 "${SCRIPT_DIR}/.cluster/credentials/monitoring.conf"

# Install kube-prometheus-stack using Helm
info "Installing kube-prometheus-stack..."

# Add Prometheus community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create values file for monitoring stack
cat > /tmp/monitoring-values.yaml <<EOF
# Prometheus configuration
prometheus:
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: ${STORAGE_CLASS:-local-path}
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi
    resources:
      requests:
        memory: 400Mi
        cpu: 100m
      limits:
        memory: 2Gi
        cpu: 1000m

# Grafana configuration
grafana:
  adminPassword: "$GRAFANA_ADMIN_PASSWORD"
  ingress:
    enabled: false  # We'll create our own ingress with OAuth
  
  # Configure Grafana
  grafana.ini:
    server:
      domain: metrics.${DOMAIN:-grafana.local}
      root_url: "https://metrics.${DOMAIN:-grafana.local}"
      serve_from_sub_path: false
    security:
      admin_user: admin
      admin_password: "$GRAFANA_ADMIN_PASSWORD"
    auth:
      disable_login_form: false
    auth.proxy:
      enabled: true
      header_name: X-WEBAUTH-USER
      header_property: username
      auto_sign_up: true
      headers: "Email:X-WEBAUTH-EMAIL"
    users:
      allow_sign_up: false
      auto_assign_org: true
      auto_assign_org_role: Viewer
  
  # Pre-configure data sources
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://prometheus-kube-prometheus-prometheus.monitoring:9090
          access: proxy
          isDefault: true
          jsonData:
            httpMethod: POST
            timeInterval: 30s
        - name: Loki
          type: loki
          url: http://loki-gateway.monitoring.svc.cluster.local
          access: proxy
          jsonData:
            httpHeaderName1: "X-Scope-OrgID"
          secureJsonData:
            httpHeaderValue1: "1"
        - name: Alertmanager
          type: alertmanager
          url: http://alertmanager-kube-prometheus-alertmanager.monitoring:9093
          access: proxy
          jsonData:
            implementation: prometheus
          
  # Pre-install useful dashboards
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          updateIntervalSeconds: 10
          allowUiUpdates: true
          options:
            path: /var/lib/grafana/dashboards/default
            
  dashboards:
    default:
      # Metrics dashboards
      kubernetes-cluster:
        gnetId: 7249
        revision: 1
        datasource: Prometheus
      kubernetes-pods:
        gnetId: 6417
        revision: 1
        datasource: Prometheus
      node-exporter:
        gnetId: 1860
        revision: 23
        datasource: Prometheus
      nginx-ingress:
        gnetId: 9614
        revision: 1
        datasource: Prometheus
      # Logging dashboards  
      loki-logs:
        gnetId: 13639
        revision: 1
        datasource: Loki
      kubernetes-logs:
        gnetId: 15141
        revision: 1
        datasource: Loki
      # Alerting dashboard
      alertmanager:
        gnetId: 9578
        revision: 4
        datasource: Prometheus

# Alertmanager configuration
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: ${STORAGE_CLASS:-local-path}
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
    resources:
      requests:
        memory: 100Mi
        cpu: 10m
      limits:
        memory: 200Mi
        cpu: 100m
    externalUrl: https://${DOMAIN:-alertmanager.local}/alertmanager
    
  config:
    global:
      resolve_timeout: 5m
      smtp_from: 'alertmanager@${DOMAIN:-local}'
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_auth_username: ''  # Configure in secret
      smtp_auth_password: ''  # Configure in secret
      
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
      routes:
        - receiver: 'critical'
          matchers:
            - severity="critical"
          continue: true
        - receiver: 'warning'
          matchers:
            - severity="warning"
          continue: true
        - receiver: 'deadman'
          matchers:
            - alertname="Watchdog"
            
    receivers:
      - name: 'default'
        webhook_configs:
          - url: 'http://control-panel.control-panel.svc.cluster.local/api/alerts'
            send_resolved: true
            
      - name: 'critical'
        webhook_configs:
          - url: 'http://control-panel.control-panel.svc.cluster.local/api/alerts/critical'
            send_resolved: true
        # email_configs:
        #   - to: 'oncall@example.com'
        #     headers:
        #       Subject: 'Critical Alert: {{ .GroupLabels.alertname }}'
            
      - name: 'warning'
        webhook_configs:
          - url: 'http://control-panel.control-panel.svc.cluster.local/api/alerts/warning'
            send_resolved: true
            
      - name: 'deadman'
        webhook_configs:
          - url: 'http://control-panel.control-panel.svc.cluster.local/api/health/alertmanager'
            
    inhibit_rules:
      - source_matchers:
          - severity="critical"
        target_matchers:
          - severity="warning"
        equal: ['alertname', 'cluster', 'service']

# Node exporter configuration
nodeExporter:
  enabled: true

# Kube-state-metrics configuration
kubeStateMetrics:
  enabled: true

# Prometheus operator configuration
prometheusOperator:
  resources:
    requests:
      cpu: 100m
      memory: 100Mi
    limits:
      cpu: 200m
      memory: 200Mi

# Disable components we don't need to save resources
kubeApiServer:
  enabled: true
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
kubeEtcd:
  enabled: false
EOF

# Install the monitoring stack
helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  -f /tmp/monitoring-values.yaml \
  -n monitoring \
  --wait

# Create additional ServiceMonitors for our applications
info "Creating ServiceMonitors for application monitoring..."

# ServiceMonitor for Gitea
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gitea
  namespace: monitoring
  labels:
    app: gitea
spec:
  namespaceSelector:
    matchNames:
      - gitea
  selector:
    matchLabels:
      app.kubernetes.io/name: gitea
  endpoints:
    - port: http
      path: /metrics
EOF

# ServiceMonitor for NGINX Ingress
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nginx-ingress
  namespace: monitoring
  labels:
    app: nginx-ingress
spec:
  namespaceSelector:
    matchNames:
      - ingress-nginx
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
  endpoints:
    - port: metrics
      path: /metrics
EOF

# Create PrometheusRule for custom alerts
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: custom-alerts
  namespace: monitoring
  labels:
    prometheus: kube-prometheus
spec:
  groups:
    - name: cluster.rules
      interval: 30s
      rules:
        - alert: HighMemoryUsage
          expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.85
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High memory usage detected"
            description: "Memory usage is above 85% on {{ \$labels.instance }}"
            
        - alert: HighCPUUsage
          expr: 100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High CPU usage detected"
            description: "CPU usage is above 80% on {{ \$labels.instance }}"
            
        - alert: DiskSpaceLow
          expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.15
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Low disk space"
            description: "Disk space is below 15% on {{ \$labels.instance }}"
            
        - alert: PodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Pod is crash looping"
            description: "Pod {{ \$labels.namespace }}/{{ \$labels.pod }} is crash looping"
EOF

# Install Loki for log aggregation
info "Installing Loki stack..."
source "${SCRIPT_DIR}/components/monitoring/install-loki.sh"

# Create additional PrometheusRules for comprehensive monitoring
info "Creating comprehensive alert rules..."

cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cluster-monitoring-rules
  namespace: monitoring
  labels:
    prometheus: kube-prometheus
spec:
  groups:
    - name: node.rules
      interval: 30s
      rules:
        # Node alerts
        - alert: NodeDown
          expr: up{job="node-exporter"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Node {{ \$labels.instance }} is down"
            description: "Node exporter on {{ \$labels.instance }} has been down for more than 5 minutes"
            runbook_url: "https://runbooks.prometheus-operator.dev/runbooks/node/nodedown"
            
        - alert: NodeHighCPU
          expr: (100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) > 85
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "High CPU usage on {{ \$labels.instance }}"
            description: "CPU usage is above 85% (current value: {{ \$value }}%)"
            
        - alert: NodeHighMemory
          expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "High memory usage on {{ \$labels.instance }}"
            description: "Memory usage is above 85% (current value: {{ \$value }}%)"
            
        - alert: NodeDiskSpaceLow
          expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.15
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Low disk space on {{ \$labels.instance }}"
            description: "Disk space is below 15% (current value: {{ \$value | humanizePercentage }})"
            
    - name: kubernetes.rules
      interval: 30s
      rules:
        - alert: KubernetesPodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Pod {{ \$labels.namespace }}/{{ \$labels.pod }} is crash looping"
            description: "Pod {{ \$labels.namespace }}/{{ \$labels.pod }} is restarting {{ \$value }} times per minute"
            
        - alert: KubernetesPodNotReady
          expr: sum by (namespace, pod) (kube_pod_status_phase{phase=~"Pending|Unknown"}) > 0
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ \$labels.namespace }}/{{ \$labels.pod }} is not ready"
            description: "Pod has been in non-ready state for more than 15 minutes"
            
        - alert: KubernetesDeploymentReplicasMismatch
          expr: kube_deployment_spec_replicas != kube_deployment_status_replicas_available
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Deployment {{ \$labels.namespace }}/{{ \$labels.deployment }} replica mismatch"
            description: "Deployment has {{ \$value }} replicas available, expected {{ \$labels.spec_replicas }}"
            
        - alert: KubernetesPVCPending
          expr: kube_persistentvolumeclaim_status_phase{phase="Pending"} == 1
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "PVC {{ \$labels.namespace }}/{{ \$labels.persistentvolumeclaim }} is pending"
            description: "PVC has been pending for more than 15 minutes"
            
    - name: application.rules
      interval: 30s
      rules:
        - alert: HighErrorRate
          expr: sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m])) by (ingress, namespace) > 0.05
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High error rate on {{ \$labels.namespace }}/{{ \$labels.ingress }}"
            description: "Error rate is {{ \$value | humanizePercentage }} errors per second"
            
        - alert: SlowResponseTime
          expr: histogram_quantile(0.95, sum(rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])) by (ingress, namespace, le)) > 1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Slow response time on {{ \$labels.namespace }}/{{ \$labels.ingress }}"
            description: "95th percentile response time is {{ \$value }}s"
            
    - name: logging.rules
      interval: 30s
      rules:
        - alert: HighLogIngestionRate
          expr: sum(rate(loki_distributor_bytes_received_total[5m])) > 100000000  # 100MB/s
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High log ingestion rate"
            description: "Log ingestion rate is {{ \$value | humanizeUnit \"Bps\" }}"
            
        - alert: LokiRequestErrors
          expr: sum(rate(loki_request_duration_seconds_count{status_code=~"5.."}[5m])) by (namespace, route) > 0.05
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Loki errors on {{ \$labels.route }}"
            description: "Error rate is {{ \$value | humanizePercentage }} errors per second"
EOF

# Deploy ingresses with OAuth2 authentication
if [[ -n "${DOMAIN:-}" ]]; then
    info "Deploying ingresses with OAuth2 authentication..."
    
    # Apply Grafana ingress
    envsubst < "${SCRIPT_DIR}/grafana-ingress.yaml" | kubectl apply -f -
    
    # Apply Prometheus ingress
    envsubst < "${SCRIPT_DIR}/prometheus-ingress.yaml" | kubectl apply -f -
    
    # Apply AlertManager ingress
    envsubst < "${SCRIPT_DIR}/alertmanager-ingress.yaml" | kubectl apply -f -
fi

# Clean up
rm -f /tmp/monitoring-values.yaml

success "Complete observability stack installed successfully"
info "=== Access Information ==="
if [[ -n "${DOMAIN:-}" ]]; then
    info "Grafana: https://metrics.${DOMAIN}"
    info "Prometheus: https://prometheus.${DOMAIN}"
    info "AlertManager: https://alerts.${DOMAIN}"
else
    info "Grafana: http://grafana.monitoring.svc.cluster.local:3000"
    info "Prometheus: http://prometheus-kube-prometheus-prometheus.monitoring:9090"
    info "AlertManager: http://alertmanager-kube-prometheus-alertmanager.monitoring:9093"
fi
info "  Admin credentials saved to: .cluster/credentials/monitoring.conf"
info "Loki: http://loki-gateway.monitoring.svc.cluster.local"
info ""
info "=== Features Enabled ==="
info "✓ Metrics collection with Prometheus"
info "✓ Log aggregation with Loki"
info "✓ Visualization with Grafana"
info "✓ Alerting with Alertmanager"
info "✓ Pre-configured dashboards and alerts"