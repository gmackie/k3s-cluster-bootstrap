#!/bin/bash
# Manage external VPS instances alongside the cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

ACTION="${1:-list}"
VPS_NAME="${2:-}"

show_usage() {
    cat << EOF
Usage: $0 [action] [vps-name] [options]

Manage external VPS instances (e.g., Gitea) alongside the K3s cluster

Actions:
    list        List all managed VPS instances
    add         Add existing VPS to management
    remove      Remove VPS from management (doesn't delete VPS)
    status      Check VPS health status
    backup      Backup VPS data
    monitor     Setup monitoring for VPS
    ssh         SSH into VPS
    deploy      Deploy/update services on VPS

Examples:
    # Add existing Gitea VPS
    $0 add gitea --ip 5.78.92.8 --domain ci.gmac.io

    # Check VPS status
    $0 status gitea

    # SSH into VPS
    $0 ssh gitea

    # Setup monitoring
    $0 monitor gitea
EOF
}

# VPS inventory file
VPS_INVENTORY="${SCRIPT_DIR}/../.cluster/vps-inventory.json"

# Initialize inventory if not exists
init_inventory() {
    if [[ ! -f "$VPS_INVENTORY" ]]; then
        echo '{"vps_instances": []}' > "$VPS_INVENTORY"
    fi
}

# List VPS instances
list_vps() {
    init_inventory
    
    info "Managed VPS Instances:"
    echo ""
    
    jq -r '.vps_instances[] | "Name: \(.name)\nIP: \(.ip)\nDomain: \(.domain)\nServices: \(.services | join(", "))\nProvider: \(.provider)\nStatus: \(.status)\n"' "$VPS_INVENTORY"
}

# Add VPS to management
add_vps() {
    local name="$VPS_NAME"
    local ip=""
    local domain=""
    local services=""
    local provider="hetzner"
    local ssh_key=""
    
    # Parse arguments
    shift 2
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ip)
                ip="$2"
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --services)
                services="$2"
                shift 2
                ;;
            --provider)
                provider="$2"
                shift 2
                ;;
            --ssh-key)
                ssh_key="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    if [[ -z "$ip" ]]; then
        error "IP address required (--ip)"
    fi
    
    info "Adding VPS: $name ($ip)"
    
    # Test SSH connection
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$ip" echo "Connected" 2>/dev/null; then
        error "Cannot connect to VPS via SSH"
    fi
    
    # Detect services if not specified
    if [[ -z "$services" ]]; then
        info "Detecting services..."
        services=$(ssh root@"$ip" "docker ps --format '{{.Names}}' 2>/dev/null || systemctl list-units --type=service --state=running --no-pager | grep -E '(gitea|nginx|postgresql)' | awk '{print \$1}' | cut -d. -f1" | tr '\n' ',' | sed 's/,$//')
    fi
    
    # Add to inventory
    init_inventory
    
    # Check if already exists
    if jq -e ".vps_instances[] | select(.name == \"$name\")" "$VPS_INVENTORY" >/dev/null; then
        info "Updating existing VPS entry..."
        jq ".vps_instances |= map(if .name == \"$name\" then . + {
            \"ip\": \"$ip\",
            \"domain\": \"$domain\",
            \"services\": [$(echo "$services" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')],
            \"provider\": \"$provider\",
            \"ssh_key\": \"$ssh_key\",
            \"updated_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"
        } else . end)" "$VPS_INVENTORY" > "$VPS_INVENTORY.tmp"
    else
        info "Adding new VPS entry..."
        jq ".vps_instances += [{
            \"name\": \"$name\",
            \"ip\": \"$ip\",
            \"domain\": \"$domain\",
            \"services\": [$(echo "$services" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')],
            \"provider\": \"$provider\",
            \"ssh_key\": \"$ssh_key\",
            \"status\": \"active\",
            \"added_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
            \"updated_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"
        }]" "$VPS_INVENTORY" > "$VPS_INVENTORY.tmp"
    fi
    
    mv "$VPS_INVENTORY.tmp" "$VPS_INVENTORY"
    
    # Setup monitoring agent
    setup_monitoring_prompt
    
    success "VPS added to management: $name"
}

# Setup monitoring agent on VPS
setup_monitoring_prompt() {
    read -p "Setup monitoring agent on VPS? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        monitor_vps
    fi
}

# Check VPS status
check_status() {
    local name="$VPS_NAME"
    
    if [[ -z "$name" ]]; then
        # Check all VPS instances
        jq -r '.vps_instances[] | .name' "$VPS_INVENTORY" | while read vps; do
            check_vps_health "$vps"
            echo ""
        done
    else
        check_vps_health "$name"
    fi
}

# Check individual VPS health
check_vps_health() {
    local name="$1"
    local vps_info=$(jq -r ".vps_instances[] | select(.name == \"$name\")" "$VPS_INVENTORY")
    
    if [[ -z "$vps_info" ]]; then
        error "VPS not found: $name"
    fi
    
    local ip=$(echo "$vps_info" | jq -r '.ip')
    local domain=$(echo "$vps_info" | jq -r '.domain')
    local services=$(echo "$vps_info" | jq -r '.services[]')
    
    info "Checking VPS: $name ($ip)"
    
    # Check SSH connectivity
    if ssh -o ConnectTimeout=5 -o BatchMode=yes root@"$ip" echo "SSH: OK" 2>/dev/null; then
        success "SSH connectivity: OK"
        
        # Check system resources
        ssh root@"$ip" << 'EOF' | sed 's/^/  /'
echo "System Resources:"
echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)% used"
echo "Memory: $(free -m | awk '/Mem:/ {printf "%.1f%% used (%dMB / %dMB)", ($2-$7)/$2*100, $2-$7, $2}')"
echo "Disk: $(df -h / | awk 'NR==2 {print $5 " used (" $3 " / " $2 ")"}')"
echo ""
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
EOF
        
        # Check services
        echo ""
        echo "  Services:"
        for service in $services; do
            if ssh root@"$ip" "docker ps | grep -q $service 2>/dev/null || systemctl is-active --quiet $service" 2>/dev/null; then
                echo "    ✓ $service: running"
            else
                echo "    ✗ $service: not running"
            fi
        done
        
        # Update status
        jq ".vps_instances |= map(if .name == \"$name\" then . + {\"status\": \"active\", \"last_check\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"} else . end)" "$VPS_INVENTORY" > "$VPS_INVENTORY.tmp"
        mv "$VPS_INVENTORY.tmp" "$VPS_INVENTORY"
    else
        error "  SSH connectivity: FAILED"
        
        # Update status
        jq ".vps_instances |= map(if .name == \"$name\" then . + {\"status\": \"unreachable\", \"last_check\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"} else . end)" "$VPS_INVENTORY" > "$VPS_INVENTORY.tmp"
        mv "$VPS_INVENTORY.tmp" "$VPS_INVENTORY"
    fi
    
    # Check HTTP if domain exists
    if [[ -n "$domain" && "$domain" != "null" ]]; then
        if curl -s -o /dev/null -w "%{http_code}" "https://$domain" | grep -q "200\|301\|302"; then
            success "  HTTPS connectivity: OK"
        else
            warn "  HTTPS connectivity: Failed"
        fi
    fi
}

# Setup monitoring on VPS
monitor_vps() {
    local name="${VPS_NAME:-$name}"
    local vps_info=$(jq -r ".vps_instances[] | select(.name == \"$name\")" "$VPS_INVENTORY")
    
    if [[ -z "$vps_info" ]]; then
        error "VPS not found: $name"
    fi
    
    local ip=$(echo "$vps_info" | jq -r '.ip')
    
    info "Setting up monitoring on VPS: $name"
    
    # Install node exporter
    ssh root@"$ip" << 'EOF'
# Download and install node exporter
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xzf node_exporter-1.7.0.linux-amd64.tar.gz
sudo cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.7.0.linux-amd64*

# Create systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'SERVICE'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=nobody
Group=nogroup
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
SERVICE

# Start service
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

# Open firewall port from cluster only
# ufw allow from <cluster-ip> to any port 9100
EOF
    
    # Add Prometheus target in cluster
    info "Adding Prometheus scrape target..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: vps-$name
  namespace: monitoring
  labels:
    app: vps-monitoring
    vps: $name
spec:
  type: ExternalName
  externalName: $ip
  ports:
  - name: metrics
    port: 9100
    targetPort: 9100
---
apiVersion: v1
kind: Endpoints
metadata:
  name: vps-$name
  namespace: monitoring
  labels:
    app: vps-monitoring
    vps: $name
subsets:
- addresses:
  - ip: $ip
  ports:
  - name: metrics
    port: 9100
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vps-$name
  namespace: monitoring
  labels:
    app: vps-monitoring
    vps: $name
spec:
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
  selector:
    matchLabels:
      app: vps-monitoring
      vps: $name
EOF
    
    success "Monitoring configured for VPS: $name"
}

# SSH into VPS
ssh_vps() {
    local name="$VPS_NAME"
    local vps_info=$(jq -r ".vps_instances[] | select(.name == \"$name\")" "$VPS_INVENTORY")
    
    if [[ -z "$vps_info" ]]; then
        error "VPS not found: $name"
    fi
    
    local ip=$(echo "$vps_info" | jq -r '.ip')
    local ssh_key=$(echo "$vps_info" | jq -r '.ssh_key // ""')
    
    if [[ -n "$ssh_key" && "$ssh_key" != "null" ]]; then
        ssh -i "$ssh_key" root@"$ip"
    else
        ssh root@"$ip"
    fi
}

# Remove VPS from management
remove_vps() {
    local name="$VPS_NAME"
    
    if [[ -z "$name" ]]; then
        error "VPS name required"
    fi
    
    warn "This will remove $name from management (VPS will not be deleted)"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove from inventory
        jq ".vps_instances |= map(select(.name != \"$name\"))" "$VPS_INVENTORY" > "$VPS_INVENTORY.tmp"
        mv "$VPS_INVENTORY.tmp" "$VPS_INVENTORY"
        
        # Remove monitoring if exists
        kubectl delete servicemonitor -n monitoring "vps-$name" 2>/dev/null || true
        kubectl delete service -n monitoring "vps-$name" 2>/dev/null || true
        kubectl delete endpoints -n monitoring "vps-$name" 2>/dev/null || true
        
        success "VPS removed from management: $name"
    fi
}

# Backup VPS
backup_vps() {
    local name="$VPS_NAME"
    local vps_info=$(jq -r ".vps_instances[] | select(.name == \"$name\")" "$VPS_INVENTORY")
    
    if [[ -z "$vps_info" ]]; then
        error "VPS not found: $name"
    fi
    
    local ip=$(echo "$vps_info" | jq -r '.ip')
    local backup_dir="${SCRIPT_DIR}/../.cluster/backups/vps-$name-$(date +%Y%m%d-%H%M%S)"
    
    info "Backing up VPS: $name to $backup_dir"
    mkdir -p "$backup_dir"
    
    # Backup strategy based on services
    local services=$(echo "$vps_info" | jq -r '.services[]')
    
    for service in $services; do
        case $service in
            gitea)
                info "Backing up Gitea..."
                ssh root@"$ip" "cd /opt/gitea && docker-compose exec -T gitea gitea dump -c /data/gitea/conf/app.ini" | \
                    cat > "$backup_dir/gitea-dump.zip"
                ;;
            postgres|postgresql)
                info "Backing up PostgreSQL..."
                ssh root@"$ip" "docker exec postgres pg_dumpall -U postgres" | \
                    gzip > "$backup_dir/postgres-dump.sql.gz"
                ;;
            *)
                info "Backing up $service config..."
                ssh root@"$ip" "tar czf - /etc/$service 2>/dev/null || true" > "$backup_dir/$service-config.tar.gz"
                ;;
        esac
    done
    
    # Backup docker-compose files if exist
    ssh root@"$ip" "tar czf - /opt/*/docker-compose.yml 2>/dev/null || true" > "$backup_dir/docker-compose-files.tar.gz"
    
    success "VPS backup completed: $backup_dir"
}

# Main execution
init_inventory

case $ACTION in
    list)
        list_vps
        ;;
    add)
        add_vps "$@"
        ;;
    remove)
        remove_vps
        ;;
    status)
        check_status
        ;;
    monitor)
        monitor_vps
        ;;
    ssh)
        ssh_vps
        ;;
    backup)
        backup_vps
        ;;
    help|*)
        show_usage
        ;;
esac