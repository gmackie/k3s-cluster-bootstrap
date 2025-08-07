#!/bin/bash

# Setup DNS records for monitoring services

echo "Setting up DNS records for monitoring services..."

# Server IP
SERVER_IP="5.78.92.8"

# Create A records
aws route53 change-resource-record-sets --hosted-zone-id Z08446523IZ5DMGMU67O \
  --change-batch "{
    \"Changes\": [
      {
        \"Action\": \"CREATE\",
        \"ResourceRecordSet\": {
          \"Name\": \"monitoring.gmac.io\",
          \"Type\": \"A\",
          \"TTL\": 300,
          \"ResourceRecords\": [{\"Value\": \"$SERVER_IP\"}]
        }
      },
      {
        \"Action\": \"CREATE\",
        \"ResourceRecordSet\": {
          \"Name\": \"metrics.gmac.io\",
          \"Type\": \"A\",
          \"TTL\": 300,
          \"ResourceRecords\": [{\"Value\": \"$SERVER_IP\"}]
        }
      },
      {
        \"Action\": \"CREATE\",
        \"ResourceRecordSet\": {
          \"Name\": \"alerts.gmac.io\",
          \"Type\": \"A\",
          \"TTL\": 300,
          \"ResourceRecords\": [{\"Value\": \"$SERVER_IP\"}]
        }
      }
    ]
  }"

echo "DNS records created:"
echo "  - monitoring.gmac.io -> $SERVER_IP (Prometheus)"
echo "  - metrics.gmac.io -> $SERVER_IP (Grafana)"
echo "  - alerts.gmac.io -> $SERVER_IP (Alertmanager)"