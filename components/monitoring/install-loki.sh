#!/bin/bash
# Loki installation for log aggregation

source "${SCRIPT_DIR}/lib/common.sh"

info "Installing Loki stack for log aggregation..."

# Add Grafana Helm repository for Loki
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create Loki values
cat > /tmp/loki-values.yaml <<EOF
# Loki configuration
loki:
  auth_enabled: false
  
  storage:
    bucketNames:
      chunks: loki-chunks
      ruler: loki-ruler
      admin: loki-admin
    type: filesystem
    
  schema_config:
    configs:
      - from: 2024-01-01
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h
          
  storage_config:
    filesystem:
      directory: /var/loki/chunks
      
  limits_config:
    retention_period: 720h  # 30 days
    enforce_metric_name: false
    reject_old_samples: true
    reject_old_samples_max_age: 168h
    max_cache_freshness_per_query: 10m
    split_queries_by_interval: 15m
    ingestion_rate_mb: 50
    ingestion_burst_size_mb: 100
    
  compactor:
    working_directory: /var/loki/retention
    retention_enabled: true
    retention_delete_delay: 2h
    retention_delete_worker_count: 150
    
  query_scheduler:
    max_outstanding_requests_per_tenant: 2048
    
# Single Binary Mode for simplicity
singleBinary:
  replicas: 1
  persistence:
    enabled: true
    size: 10Gi
    storageClass: ${STORAGE_CLASS:-local-path}
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 1Gi

# Disable other components in single binary mode
read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0

# Gateway configuration
gateway:
  enabled: true
  ingress:
    enabled: false  # We'll use service for internal access

# Monitoring
monitoring:
  dashboards:
    enabled: true
    namespace: monitoring
  rules:
    enabled: true
    namespace: monitoring
  serviceMonitor:
    enabled: true
    namespace: monitoring
  selfMonitoring:
    enabled: false
    grafanaAgent:
      installOperator: false
EOF

# Install Loki
helm upgrade --install loki grafana/loki \
  -f /tmp/loki-values.yaml \
  -n monitoring \
  --wait

# Install Promtail for log collection
info "Installing Promtail for log collection..."

cat > /tmp/promtail-values.yaml <<EOF
# Promtail configuration
config:
  clients:
    - url: http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push
      
  snippets:
    pipelineStages:
      - cri: {}
      - json:
          expressions:
            stream: stream
            time: time
            level: level
            msg: msg
            namespace: namespace
            pod: pod
            container: container
      - labels:
          level:
          namespace:
          pod:
          container:
      - match:
          selector: '{namespace="kube-system"}'
          stages:
            - drop:
                expression: '.*kube-probe.*'
      - match:
          selector: '{namespace="monitoring"}'
          stages:
            - regex:
                expression: '.*level=(?P<level>\\w+).*'
            - labels:
                level:
                
  # Additional scrape configs for system logs
  extraScrapeConfigs: |
    - job_name: journal
      journal:
        path: /var/log/journal
        max_age: 12h
        labels:
          job: systemd-journal
      relabel_configs:
        - source_labels: ['__journal__systemd_unit']
          target_label: 'unit'
        - source_labels: ['__journal__hostname']
          target_label: 'hostname'
    - job_name: syslog
      static_configs:
        - targets:
            - localhost
          labels:
            job: syslog
            __path__: /var/log/syslog

# DaemonSet configuration
daemonSet:
  enabled: true
  
tolerations:
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
    
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi
    
# Mount additional paths
extraVolumes:
  - name: journal
    hostPath:
      path: /var/log/journal
  - name: syslog
    hostPath:
      path: /var/log
  - name: pods
    hostPath:
      path: /var/log/pods
  - name: docker
    hostPath:
      path: /var/lib/docker/containers
      
extraVolumeMounts:
  - name: journal
    mountPath: /var/log/journal
    readOnly: true
  - name: syslog
    mountPath: /var/log
    readOnly: true
  - name: pods
    mountPath: /var/log/pods
    readOnly: true
  - name: docker
    mountPath: /var/lib/docker/containers
    readOnly: true

# Service monitor for metrics
serviceMonitor:
  enabled: true
EOF

# Install Promtail
helm upgrade --install promtail grafana/promtail \
  -f /tmp/promtail-values.yaml \
  -n monitoring \
  --wait

# Clean up temporary files
rm -f /tmp/loki-values.yaml /tmp/promtail-values.yaml

success "Loki stack installed successfully"
info "Logs are being collected by Promtail and stored in Loki"
info "Access logs through Grafana data sources"