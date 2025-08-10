# Monitoring Integration Guide

## Quick Setup

1. **Create GitHub OAuth Apps:**
   ```bash
   ./setup-oauth-monitoring.sh
   ```
   Follow the prompts to create 3 OAuth apps on GitHub.

2. **Deploy to Server:**
   ```bash
   ./deploy-monitoring.sh
   ```

## Service URLs

- **Prometheus**: https://monitoring.gmac.io
- **Grafana**: https://metrics.gmac.io  
- **Alertmanager**: https://alerts.gmac.io

All services require GitHub authentication (restricted to user: gmackie).

## Adding Metrics to Your Projects

### Docker Containers

Add these labels to any container you want to monitor:

```yaml
services:
  my-app:
    image: my-app:latest
    labels:
      - "prometheus.io/scrape=true"
      - "prometheus.io/port=8080"
      - "prometheus.io/job=my-app"
      - "prometheus.io/path=/metrics"  # optional, defaults to /metrics
```

### Application Metrics

Expose Prometheus metrics in your application:

**Node.js Example:**
```javascript
const prometheus = require('prom-client');
const express = require('express');

const app = express();
prometheus.collectDefaultMetrics();

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', prometheus.register.contentType);
  res.end(await prometheus.register.metrics());
});
```

**Go Example:**
```go
import (
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

http.Handle("/metrics", promhttp.Handler())
```

## Custom Alerts

Add alert rules to `/opt/monitoring/prometheus/rules/custom.yml`:

```yaml
groups:
  - name: my_app_alerts
    rules:
      - alert: HighRequestRate
        expr: rate(http_requests_total[5m]) > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High request rate on {{ $labels.instance }}"
```

## Grafana Dashboards

1. Create dashboard in Grafana UI
2. Export as JSON
3. Save to `/opt/monitoring/grafana/dashboards/`
4. Restart Grafana container

## Webhook Notifications

Configure in `/opt/monitoring/alertmanager/config.yml`:

```yaml
receivers:
  - name: 'my-webhook'
    webhook_configs:
      - url: 'https://my-app.com/alerts'
        send_resolved: true
```

## Troubleshooting

Check service status:
```bash
ssh root@5.78.92.8 'cd /opt/monitoring && docker-compose -f docker-compose-oauth.yml ps'
```

View logs:
```bash
ssh root@5.78.92.8 'cd /opt/monitoring && docker-compose -f docker-compose-oauth.yml logs -f [service]'
```

Services: oauth2-proxy-prometheus, oauth2-proxy-grafana, oauth2-proxy-alertmanager, prometheus, grafana, alertmanager