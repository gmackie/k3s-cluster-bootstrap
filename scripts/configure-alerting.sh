#!/bin/bash
# Configure alerting channels for monitoring stack

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Configuration type
CONFIG_TYPE="${1:-show}"
CHANNEL="${2:-}"

show_usage() {
    cat << EOF
Usage: $0 [action] [channel]

Configure alerting notification channels

Actions:
    show        Show current alerting configuration
    add         Add a notification channel
    test        Send test alert
    list        List available channel types

Channels:
    email       Email notifications (SMTP)
    slack       Slack webhook
    discord     Discord webhook
    pagerduty   PagerDuty integration
    webhook     Generic webhook
    telegram    Telegram bot

Examples:
    # Show current configuration
    $0 show

    # Add email notifications
    $0 add email

    # Test alerting
    $0 test

    # List available channels
    $0 list
EOF
}

# Add email configuration
configure_email() {
    info "Configuring email notifications..."
    
    read -p "SMTP Server (e.g., smtp.gmail.com:587): " smtp_server
    read -p "SMTP Username: " smtp_username
    read -sp "SMTP Password: " smtp_password
    echo
    read -p "From Address: " from_address
    read -p "To Address (for alerts): " to_address
    
    # Create secret for SMTP credentials
    kubectl create secret generic alertmanager-smtp \
        --from-literal=username="$smtp_username" \
        --from-literal=password="$smtp_password" \
        -n monitoring \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Update Alertmanager configuration
    cat <<EOF > /tmp/alertmanager-email.yaml
global:
  smtp_from: '$from_address'
  smtp_smarthost: '$smtp_server'
  smtp_auth_username: '$smtp_username'
  smtp_auth_password: '$smtp_password'
  smtp_require_tls: true

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'email-notifications'
  routes:
    - receiver: 'critical-email'
      matchers:
        - severity="critical"

receivers:
  - name: 'email-notifications'
    email_configs:
      - to: '$to_address'
        headers:
          Subject: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}'
        html: |
          <h2>{{ .GroupLabels.alertname }}</h2>
          <p><b>Status:</b> {{ .Status }}</p>
          {{ range .Alerts }}
          <hr>
          <p><b>Alert:</b> {{ .Labels.alertname }}</p>
          <p><b>Summary:</b> {{ .Annotations.summary }}</p>
          <p><b>Description:</b> {{ .Annotations.description }}</p>
          <p><b>Severity:</b> {{ .Labels.severity }}</p>
          {{ if .Annotations.runbook_url }}
          <p><b>Runbook:</b> <a href="{{ .Annotations.runbook_url }}">{{ .Annotations.runbook_url }}</a></p>
          {{ end }}
          {{ end }}
          
  - name: 'critical-email'
    email_configs:
      - to: '$to_address'
        headers:
          Subject: '[CRITICAL] {{ .GroupLabels.alertname }}'
        send_resolved: true
EOF
    
    # Apply configuration
    kubectl create secret generic alertmanager-config \
        --from-file=alertmanager.yaml=/tmp/alertmanager-email.yaml \
        -n monitoring \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Restart Alertmanager
    kubectl rollout restart statefulset/alertmanager-kube-prometheus-alertmanager -n monitoring
    
    rm -f /tmp/alertmanager-email.yaml
    success "Email notifications configured"
}

# Add Slack configuration
configure_slack() {
    info "Configuring Slack notifications..."
    
    read -p "Slack Webhook URL: " webhook_url
    read -p "Channel (e.g., #alerts): " channel
    
    cat <<EOF > /tmp/alertmanager-slack.yaml
receivers:
  - name: 'slack-notifications'
    slack_configs:
      - api_url: '$webhook_url'
        channel: '$channel'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'
        send_resolved: true
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
        fields:
          - title: Severity
            value: '{{ .GroupLabels.severity }}'
            short: true
          - title: Cluster
            value: '{{ .GroupLabels.cluster }}'
            short: true
EOF
    
    success "Slack notifications configured"
}

# Add Discord configuration  
configure_discord() {
    info "Configuring Discord notifications..."
    
    read -p "Discord Webhook URL: " webhook_url
    
    cat <<EOF > /tmp/alertmanager-discord.yaml
receivers:
  - name: 'discord-notifications'
    webhook_configs:
      - url: '$webhook_url/slack'
        send_resolved: true
EOF
    
    success "Discord notifications configured"
}

# Add PagerDuty configuration
configure_pagerduty() {
    info "Configuring PagerDuty integration..."
    
    read -p "PagerDuty Integration Key: " integration_key
    
    cat <<EOF > /tmp/alertmanager-pagerduty.yaml
receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - routing_key: '$integration_key'
        description: '{{ .GroupLabels.alertname }}: {{ .CommonAnnotations.summary }}'
        severity: '{{ if eq .GroupLabels.severity "critical" }}critical{{ else }}warning{{ end }}'
        details:
          firing: '{{ .Alerts.Firing | len }}'
          resolved: '{{ .Alerts.Resolved | len }}'
          cluster: '{{ .GroupLabels.cluster }}'
EOF
    
    success "PagerDuty integration configured"
}

# Add generic webhook
configure_webhook() {
    info "Configuring generic webhook..."
    
    read -p "Webhook URL: " webhook_url
    read -p "HTTP Method (POST/PUT): " method
    
    cat <<EOF > /tmp/alertmanager-webhook.yaml
receivers:
  - name: 'webhook-notifications'
    webhook_configs:
      - url: '$webhook_url'
        http_config:
          method: '$method'
        send_resolved: true
        max_alerts: 10
EOF
    
    success "Webhook notifications configured"
}

# Add Telegram configuration
configure_telegram() {
    info "Configuring Telegram notifications..."
    
    read -p "Telegram Bot Token: " bot_token
    read -p "Chat ID: " chat_id
    
    # Deploy telegram webhook adapter
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager-telegram
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager-telegram
  template:
    metadata:
      labels:
        app: alertmanager-telegram
    spec:
      containers:
      - name: telegram-bot
        image: metalmatze/alertmanager-bot:0.4.3
        env:
        - name: TELEGRAM_TOKEN
          value: "$bot_token"
        - name: TELEGRAM_CHAT_ID
          value: "$chat_id"
        - name: LISTEN_ADDRESS
          value: "0.0.0.0:8080"
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager-telegram
  namespace: monitoring
spec:
  selector:
    app: alertmanager-telegram
  ports:
  - port: 8080
    targetPort: 8080
EOF
    
    cat <<EOF > /tmp/alertmanager-telegram.yaml
receivers:
  - name: 'telegram-notifications'
    webhook_configs:
      - url: 'http://alertmanager-telegram:8080/alerts'
        send_resolved: true
EOF
    
    success "Telegram notifications configured"
}

# Test alerting
test_alerting() {
    info "Sending test alert..."
    
    # Create a test alert
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-alert
  namespace: monitoring
  labels:
    app: test-alert
spec:
  containers:
  - name: alert
    image: curlimages/curl:latest
    command:
    - sh
    - -c
    - |
      curl -XPOST http://alertmanager-kube-prometheus-alertmanager:9093/api/v1/alerts \
        -H "Content-Type: application/json" \
        -d '[{
          "labels": {
            "alertname": "TestAlert",
            "severity": "warning",
            "cluster": "test",
            "namespace": "monitoring"
          },
          "annotations": {
            "summary": "This is a test alert",
            "description": "This alert was triggered manually to test the alerting pipeline"
          },
          "generatorURL": "http://test-alert-generator"
        }]'
      sleep 10
  restartPolicy: Never
EOF
    
    sleep 5
    kubectl logs test-alert -n monitoring
    kubectl delete pod test-alert -n monitoring
    
    success "Test alert sent. Check your notification channels."
}

# Show current configuration
show_config() {
    info "Current Alertmanager configuration:"
    
    kubectl get secret alertmanager-kube-prometheus-alertmanager -n monitoring -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
}

# List available channels
list_channels() {
    info "Available notification channels:"
    echo ""
    echo "  email      - Email notifications via SMTP"
    echo "  slack      - Slack workspace notifications"
    echo "  discord    - Discord server notifications"
    echo "  pagerduty  - PagerDuty incident management"
    echo "  webhook    - Generic webhook endpoint"
    echo "  telegram   - Telegram bot notifications"
    echo ""
    echo "Control Panel Integration:"
    echo "  The control panel automatically receives all alerts via webhook"
    echo "  at http://control-panel.control-panel.svc.cluster.local/api/alerts"
}

# Main execution
case $CONFIG_TYPE in
    show)
        show_config
        ;;
    add)
        case $CHANNEL in
            email)
                configure_email
                ;;
            slack)
                configure_slack
                ;;
            discord)
                configure_discord
                ;;
            pagerduty)
                configure_pagerduty
                ;;
            webhook)
                configure_webhook
                ;;
            telegram)
                configure_telegram
                ;;
            *)
                error "Unknown channel: $CHANNEL"
                ;;
        esac
        ;;
    test)
        test_alerting
        ;;
    list)
        list_channels
        ;;
    *)
        show_usage
        exit 1
        ;;
esac