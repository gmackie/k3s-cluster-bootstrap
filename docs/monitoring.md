# Monitoring Stack Documentation

The K3s cluster includes a comprehensive observability stack with metrics, logs, visualization, and alerting.

## Components

### 1. Prometheus (Metrics)
- **Purpose**: Collects and stores time-series metrics
- **Features**:
  - Auto-discovery of Kubernetes resources
  - 30-day retention policy
  - Node, pod, and application metrics
  - Custom metrics via ServiceMonitors

### 2. Grafana (Visualization)
- **Purpose**: Visualizes metrics and logs
- **Access**: `https://<domain>/grafana`
- **Features**:
  - Pre-configured dashboards
  - Prometheus and Loki data sources
  - Alert visualization
  - Custom dashboard creation

### 3. Loki (Log Aggregation)
- **Purpose**: Centralized log storage and querying
- **Features**:
  - Efficient log indexing
  - 30-day retention
  - Label-based queries
  - Integration with Grafana

### 4. Promtail (Log Collection)
- **Purpose**: Ships logs from all nodes to Loki
- **Features**:
  - Runs on every node (DaemonSet)
  - Collects container logs
  - System journal logs
  - Log parsing and labeling

### 5. Alertmanager (Alerting)
- **Purpose**: Manages alerts and notifications
- **Features**:
  - Alert grouping and deduplication
  - Multiple notification channels
  - Alert silencing and inhibition
  - Integration with control panel

## Pre-configured Dashboards

1. **Kubernetes Cluster Overview** - Overall cluster health
2. **Kubernetes Pod Monitoring** - Pod-level metrics
3. **Node Exporter** - System-level metrics
4. **NGINX Ingress** - Ingress controller metrics
5. **Loki Logs** - Log exploration
6. **Kubernetes Logs** - Container log analysis
7. **Alertmanager** - Alert overview

## Alert Rules

### Node Alerts
- `NodeDown` - Node is unreachable
- `NodeHighCPU` - CPU usage > 85%
- `NodeHighMemory` - Memory usage > 85%
- `NodeDiskSpaceLow` - Disk space < 15%

### Kubernetes Alerts
- `KubernetesPodCrashLooping` - Pod restart loop
- `KubernetesPodNotReady` - Pod not ready > 15m
- `KubernetesDeploymentReplicasMismatch` - Deployment issues
- `KubernetesPVCPending` - Storage claim pending

### Application Alerts
- `HighErrorRate` - HTTP 5xx errors > 5%
- `SlowResponseTime` - 95th percentile > 1s

### Logging Alerts
- `HighLogIngestionRate` - > 100MB/s
- `LokiRequestErrors` - Loki query errors

## Notification Channels

Configure alerting channels using the provided script:

```bash
# List available channels
./scripts/configure-alerting.sh list

# Add email notifications
./scripts/configure-alerting.sh add email

# Add Slack notifications
./scripts/configure-alerting.sh add slack

# Test alerting
./scripts/configure-alerting.sh test
```

Supported channels:
- Email (SMTP)
- Slack
- Discord
- PagerDuty
- Telegram
- Generic webhooks

## Querying Logs

### Using Grafana
1. Navigate to Grafana (`https://<domain>/grafana`)
2. Go to Explore
3. Select Loki data source
4. Use LogQL queries

### LogQL Examples

```logql
# All logs from a namespace
{namespace="gitea"}

# Logs from specific pod
{pod="control-panel-xxxxx"}

# Error logs
{namespace="production"} |= "error"

# JSON parsing
{app="myapp"} | json | level="error"

# Rate of errors
rate({namespace="production"} |= "error" [5m])
```

## Metrics Queries

### PromQL Examples

```promql
# CPU usage by node
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Pod restart rate
rate(kube_pod_container_status_restarts_total[15m])

# HTTP error rate
sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m])) by (ingress)
```

## Health Checks

Check monitoring stack health:

```bash
# Full health check
./scripts/monitoring-health.sh

# Check specific component
kubectl get pods -n monitoring
kubectl logs -n monitoring <pod-name>
```

## Storage and Retention

### Metrics (Prometheus)
- Retention: 30 days
- Storage: 20GB PVC
- Compaction: Automatic

### Logs (Loki)
- Retention: 30 days
- Storage: 10GB PVC
- Indexing: By timestamp and labels

### Adjusting Retention

To modify retention periods, update the monitoring component values:
- Prometheus: `retention: 30d` in prometheus spec
- Loki: `retention_period: 720h` in limits_config

## Troubleshooting

### No metrics available
1. Check metrics-server: `kubectl get deployment metrics-server -n kube-system`
2. Verify ServiceMonitors: `kubectl get servicemonitor -n monitoring`
3. Check Prometheus targets: Access Prometheus UI → Status → Targets

### No logs in Grafana
1. Check Promtail pods: `kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail`
2. Verify Loki is running: `kubectl get pods -n monitoring -l app.kubernetes.io/name=loki`
3. Check Promtail logs: `kubectl logs -n monitoring -l app.kubernetes.io/name=promtail`

### Alerts not firing
1. Check Alertmanager: `kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager`
2. Verify alert rules: `kubectl get prometheusrule -n monitoring`
3. Test with manual alert: `./scripts/configure-alerting.sh test`

### High resource usage
1. Reduce retention periods
2. Adjust resource limits in values
3. Enable sampling for high-volume logs
4. Use more specific label selectors

## Best Practices

1. **Label your applications** - Use consistent labels for better filtering
2. **Create ServiceMonitors** - Expose custom metrics
3. **Use structured logging** - JSON logs for better parsing
4. **Set up PagerDuty** - For critical production alerts
5. **Regular backups** - Backup Grafana dashboards and alert rules
6. **Monitor the monitors** - Set up deadman's switch alerts
7. **Document runbooks** - Link runbooks in alert annotations