#!/bin/bash

# Setup script for monitoring stack

set -e

echo "Setting up monitoring stack for gmac.io..."

# Create directories
echo "Creating necessary directories..."
mkdir -p monitoring/prometheus/rules
mkdir -p monitoring/grafana/{provisioning/{datasources,dashboards},dashboards}
mkdir -p monitoring/alertmanager/templates
mkdir -p monitoring/exporters/blackbox

# Create .env file if it doesn't exist
if [ ! -f monitoring/.env ]; then
    echo "Creating .env file..."
    cat > monitoring/.env << EOF
# Grafana admin credentials
GRAFANA_USER=admin
GRAFANA_PASSWORD=$(openssl rand -base64 12)

# Alerting webhooks (optional)
# SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
# DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR/WEBHOOK/URL
EOF
    echo "Generated Grafana admin password in monitoring/.env"
fi

# Download pre-built Grafana dashboards
echo "Downloading Grafana dashboards..."

# Node Exporter Full dashboard
curl -s https://grafana.com/api/dashboards/1860/revisions/latest/download \
    -o monitoring/grafana/dashboards/node-exporter-full.json

# Docker and Container dashboard
curl -s https://grafana.com/api/dashboards/893/revisions/latest/download \
    -o monitoring/grafana/dashboards/docker-containers.json

# Prometheus Stats dashboard
curl -s https://grafana.com/api/dashboards/2/revisions/latest/download \
    -o monitoring/grafana/dashboards/prometheus-stats.json

# Create custom overview dashboard
cat > monitoring/grafana/dashboards/overview.json << 'EOF'
{
  "dashboard": {
    "title": "GMAC.IO Overview",
    "panels": [
      {
        "title": "Service Status",
        "targets": [
          {
            "expr": "up",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "title": "CPU Usage",
        "targets": [
          {
            "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      }
    ],
    "schemaVersion": 16,
    "version": 0
  }
}
EOF

# Set permissions
chmod 600 monitoring/.env

# Start the monitoring stack
echo ""
echo "Setup complete! To start the monitoring stack:"
echo ""
echo "  cd monitoring"
echo "  docker-compose up -d"
echo ""
echo "Access points:"
echo "  - Prometheus: http://localhost:9090"
echo "  - Grafana: http://localhost:3001 (admin/check .env for password)"
echo "  - Alertmanager: http://localhost:9093"
echo ""
echo "To integrate with projects, add these labels to containers:"
echo '  labels:'
echo '    - "prometheus.io/scrape=true"'
echo '    - "prometheus.io/port=8080"'
echo '    - "prometheus.io/job=my-service"'
echo ""
echo "For production deployment with nginx:"
echo "  - Prometheus: https://ci.gmac.io/prometheus"
echo "  - Grafana: https://ci.gmac.io/grafana"
echo "  - Alertmanager: https://ci.gmac.io/alertmanager"