# Centralized Monitoring Stack

This is a modular monitoring solution using Prometheus, Grafana, and Alertmanager designed to monitor all gmac.io infrastructure and projects.

## Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌───────────────┐
│   Applications  │────▶│  Prometheus  │────▶│   Grafana     │
│   & Exporters   │     │              │     │ (Dashboards)  │
└─────────────────┘     └──────┬───────┘     └───────────────┘
                               │
                               ▼
                        ┌──────────────┐
                        │ Alertmanager │
                        │   (Alerts)   │
                        └──────────────┘
```

## Components

- **Prometheus**: Time-series database for metrics collection
- **Grafana**: Visualization and dashboards
- **Alertmanager**: Alert routing and notifications
- **Node Exporter**: System metrics (CPU, memory, disk)
- **cAdvisor**: Container metrics
- **Blackbox Exporter**: Endpoint monitoring
- **Postgres Exporter**: Database metrics

## Quick Start

1. Run the setup script:
   ```bash
   cd monitoring
   ./setup-monitoring.sh
   ```

2. Start the stack:
   ```bash
   docker-compose up -d
   ```

3. Access the services:
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:3001 (admin/check .env)
   - Alertmanager: http://localhost:9093

## Integration Guide

### For Docker Containers

Add these labels to your containers:

```yaml
labels:
  - "prometheus.io/scrape=true"
  - "prometheus.io/port=8080"
  - "prometheus.io/job=my-service"
```

### For Applications

Expose metrics in Prometheus format at `/metrics`:

```go
// Go example
import "github.com/prometheus/client_golang/prometheus/promhttp"

http.Handle("/metrics", promhttp.Handler())
```

### For Kubernetes

The stack auto-discovers Kubernetes services. Add these annotations:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

## Modular Deployment

This monitoring stack is designed to be modular. You can:

1. **Run centralized**: Single instance monitoring all projects
2. **Run per-project**: Copy and customize for individual projects
3. **Mix approach**: Central monitoring with project-specific exporters

### Extracting for Standalone Use

To use this monitoring stack for a specific project:

```bash
# Copy the monitoring directory
cp -r monitoring /path/to/project/

# Update prometheus.yml to only monitor your project
# Update docker-compose.yml network configuration
# Customize alerting rules
```

## Configuration

### Adding New Targets

Edit `prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'my-new-service'
    static_configs:
      - targets: ['service:port']
```

### Custom Alerts

Add rules to `prometheus/rules/`:

```yaml
groups:
  - name: custom_alerts
    rules:
      - alert: MyAlert
        expr: metric_name > threshold
        for: 5m
        labels:
          severity: warning
```

### Grafana Dashboards

1. Create in UI and export JSON
2. Save to `grafana/dashboards/`
3. Restart Grafana to auto-load

## Alert Destinations

Configure in `alertmanager/config.yml`:

- Email (SMTP)
- Slack webhooks
- Discord webhooks
- Custom webhooks
- PagerDuty
- OpsGenie

## Retention & Storage

Default retention: 30 days

To change, modify in docker-compose.yml:
```yaml
command:
  - '--storage.tsdb.retention.time=90d'
```

## Security

1. Change default Grafana password in `.env`
2. Use nginx reverse proxy with auth for production
3. Restrict network access to metrics endpoints
4. Use TLS for external access

## Backup

Important data to backup:
- `prometheus_data` volume (metrics)
- `grafana_data` volume (dashboards/settings)
- Configuration files

## Troubleshooting

Check service logs:
```bash
docker-compose logs prometheus
docker-compose logs grafana
docker-compose logs alertmanager
```

Verify targets in Prometheus:
- http://localhost:9090/targets

Test alerting:
- http://localhost:9090/alerts

## Resource Usage

Approximate requirements:
- Prometheus: 2GB RAM, 50GB disk for 30-day retention
- Grafana: 512MB RAM
- Exporters: 100MB RAM each

Adjust based on:
- Number of metrics
- Scrape frequency
- Retention period

## Extension Points

1. **Custom Exporters**: Add to docker-compose.yml
2. **Service Discovery**: Configure in prometheus.yml
3. **Dashboards**: Import from grafana.com or create custom
4. **Alerts**: Add domain-specific rules
5. **Integrations**: Use remote_write for long-term storage