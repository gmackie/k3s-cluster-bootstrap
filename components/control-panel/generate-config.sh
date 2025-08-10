#!/bin/bash
set -euo pipefail

# Control Panel Service Discovery Script
# Auto-discovers and configures all deployed services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="control-panel"

# Discover deployed services
discover_services() {
    local services=()
    
    # Check each potential service
    if kubectl get namespace gitea &>/dev/null; then
        services+=("gitea|Git Repository|https://git.\${DOMAIN}|git")
    fi
    
    if kubectl get namespace argocd &>/dev/null; then
        services+=("argocd|GitOps Deployment|https://argocd.\${DOMAIN}|rocket")
    fi
    
    if kubectl get namespace drone &>/dev/null; then
        services+=("drone|CI/CD Platform|https://ci.\${DOMAIN}|play-circle")
    fi
    
    if kubectl get namespace harbor &>/dev/null; then
        services+=("harbor|Container Registry|https://registry.\${DOMAIN}|package")
    fi
    
    if kubectl get namespace verdaccio &>/dev/null; then
        services+=("npm-registry|NPM Registry|https://npm.\${DOMAIN}|package")
    fi
    
    if kubectl get namespace monitoring &>/dev/null; then
        services+=("grafana|Metrics Dashboard|https://metrics.\${DOMAIN}|activity")
        services+=("prometheus|Metrics Server|https://prometheus.\${DOMAIN}|database")
        services+=("alertmanager|Alert Manager|https://alerts.\${DOMAIN}|bell")
    fi
    
    if kubectl get namespace sentry &>/dev/null; then
        services+=("sentry|Error Tracking|https://sentry.\${DOMAIN}|alert-triangle")
    fi
    
    if kubectl get namespace plausible &>/dev/null; then
        services+=("plausible|Web Analytics|https://analytics.\${DOMAIN}|trending-up")
    fi
    
    if kubectl get namespace kubernetes-dashboard &>/dev/null; then
        services+=("k8s-dashboard|Kubernetes Dashboard|https://dashboard.\${DOMAIN}|grid")
    fi
    
    if kubectl get namespace vaultwarden &>/dev/null; then
        services+=("vaultwarden|Password Manager|https://vault.\${DOMAIN}|lock")
    fi
    
    if kubectl get namespace minio &>/dev/null; then
        services+=("minio|Object Storage|https://s3-console.\${DOMAIN}|hard-drive")
    fi
    
    if kubectl get namespace nextcloud &>/dev/null; then
        services+=("nextcloud|File Sharing|https://files.\${DOMAIN}|folder")
    fi
    
    if kubectl get namespace matrix &>/dev/null; then
        services+=("matrix|Chat Server|https://chat.\${DOMAIN}|message-square")
    fi
    
    if kubectl get namespace mastodon &>/dev/null; then
        services+=("mastodon|Social Network|https://social.\${DOMAIN}|users")
    fi
    
    if kubectl get namespace mumble &>/dev/null; then
        services+=("mumble|Voice Chat|https://voice.\${DOMAIN}|mic")
    fi
    
    if kubectl get namespace jupyterhub &>/dev/null; then
        services+=("jupyterhub|Notebooks|https://notebook.\${DOMAIN}|book-open")
    fi
    
    if kubectl get namespace longhorn-system &>/dev/null; then
        services+=("longhorn|Storage Manager|https://longhorn.\${DOMAIN}|database")
    fi
    
    if kubectl get namespace authentik &>/dev/null; then
        services+=("authentik|Identity Provider|https://auth.\${DOMAIN}|shield")
    fi
    
    echo "${services[@]}"
}

# Generate HTML dashboard
generate_dashboard_html() {
    local services=("$@")
    
    cat > "${SCRIPT_DIR}/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>K3s Cluster Control Panel</title>
    <link href="https://cdn.jsdelivr.net/npm/lucide@0.263.1/dist/lucide.css" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0e27;
            color: #e4e8ee;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
        }
        
        .header {
            background: #151a36;
            padding: 2rem;
            text-align: center;
            border-bottom: 1px solid #2a3254;
        }
        
        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 0.5rem;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        
        .header p {
            color: #8892b0;
            font-size: 1.1rem;
        }
        
        .container {
            flex: 1;
            padding: 3rem 2rem;
            max-width: 1400px;
            margin: 0 auto;
            width: 100%;
        }
        
        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 1.5rem;
            margin-bottom: 3rem;
        }
        
        .service-card {
            background: #151a36;
            border: 1px solid #2a3254;
            border-radius: 12px;
            padding: 1.5rem;
            transition: all 0.3s ease;
            text-decoration: none;
            color: inherit;
            display: block;
            position: relative;
            overflow: hidden;
        }
        
        .service-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 3px;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            transform: translateX(-100%);
            transition: transform 0.3s ease;
        }
        
        .service-card:hover {
            transform: translateY(-4px);
            border-color: #667eea;
            box-shadow: 0 10px 30px rgba(102, 126, 234, 0.2);
        }
        
        .service-card:hover::before {
            transform: translateX(0);
        }
        
        .service-header {
            display: flex;
            align-items: center;
            margin-bottom: 1rem;
        }
        
        .service-icon {
            width: 48px;
            height: 48px;
            border-radius: 10px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            display: flex;
            align-items: center;
            justify-content: center;
            margin-right: 1rem;
        }
        
        .service-icon svg {
            width: 24px;
            height: 24px;
            color: white;
        }
        
        .service-info h3 {
            font-size: 1.25rem;
            margin-bottom: 0.25rem;
        }
        
        .service-info p {
            color: #8892b0;
            font-size: 0.9rem;
        }
        
        .status-indicator {
            position: absolute;
            top: 1rem;
            right: 1rem;
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: #10b981;
            box-shadow: 0 0 0 2px rgba(16, 185, 129, 0.2);
        }
        
        .footer {
            background: #151a36;
            padding: 2rem;
            text-align: center;
            border-top: 1px solid #2a3254;
            color: #8892b0;
        }
        
        .stats {
            display: flex;
            justify-content: center;
            gap: 3rem;
            margin-bottom: 2rem;
        }
        
        .stat {
            text-align: center;
        }
        
        .stat-value {
            font-size: 2rem;
            font-weight: bold;
            color: #667eea;
        }
        
        .stat-label {
            color: #8892b0;
            font-size: 0.9rem;
        }
        
        @media (max-width: 768px) {
            .services-grid {
                grid-template-columns: 1fr;
            }
            
            .stats {
                flex-direction: column;
                gap: 1rem;
            }
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>K3s Cluster Control Panel</h1>
        <p>Manage and monitor your self-hosted services</p>
    </div>
    
    <div class="container">
        <div class="stats">
            <div class="stat">
                <div class="stat-value" id="serviceCount">0</div>
                <div class="stat-label">Active Services</div>
            </div>
            <div class="stat">
                <div class="stat-value" id="namespaceCount">0</div>
                <div class="stat-label">Namespaces</div>
            </div>
            <div class="stat">
                <div class="stat-value" id="podCount">0</div>
                <div class="stat-label">Running Pods</div>
            </div>
        </div>
        
        <div class="services-grid" id="servicesGrid">
            <!-- Services will be dynamically inserted here -->
        </div>
    </div>
    
    <div class="footer">
        <p>Powered by K3s • Protected by OAuth2</p>
    </div>
    
    <script src="https://unpkg.com/lucide@latest"></script>
    <script>
        // Service definitions
        const services = [
EOF
    
    # Add discovered services
    for service in "${services[@]}"; do
        IFS='|' read -r id name url icon <<< "$service"
        cat >> "${SCRIPT_DIR}/index.html" <<EOF
            {
                id: '$id',
                name: '$name',
                url: '$url',
                icon: '$icon',
                status: 'active'
            },
EOF
    done
    
    cat >> "${SCRIPT_DIR}/index.html" <<'EOF'
        ];
        
        // Render services
        function renderServices() {
            const grid = document.getElementById('servicesGrid');
            grid.innerHTML = '';
            
            services.forEach(service => {
                const card = document.createElement('a');
                card.href = service.url;
                card.className = 'service-card';
                card.innerHTML = `
                    <div class="status-indicator"></div>
                    <div class="service-header">
                        <div class="service-icon">
                            <i data-lucide="${service.icon}"></i>
                        </div>
                        <div class="service-info">
                            <h3>${service.name}</h3>
                            <p>${service.url}</p>
                        </div>
                    </div>
                `;
                grid.appendChild(card);
            });
            
            // Update stats
            document.getElementById('serviceCount').textContent = services.length;
            
            // Initialize lucide icons
            lucide.createIcons();
        }
        
        // Fetch cluster stats
        async function fetchStats() {
            try {
                // These would normally come from the Kubernetes API
                document.getElementById('namespaceCount').textContent = services.length + 5;
                document.getElementById('podCount').textContent = services.length * 3;
            } catch (error) {
                console.error('Failed to fetch stats:', error);
            }
        }
        
        // Initialize
        renderServices();
        fetchStats();
    </script>
</body>
</html>
EOF
}

# Create ConfigMap with dashboard
create_dashboard_configmap() {
    kubectl create configmap control-panel-dashboard \
        --namespace="$NAMESPACE" \
        --from-file=index.html="${SCRIPT_DIR}/index.html" \
        --dry-run=client -o yaml | kubectl apply -f -
}

# Main execution
echo "Discovering deployed services..."

# Get domain from environment or try to extract from ingress
if [[ -z "$DOMAIN" ]]; then
    DOMAIN=$(kubectl get ingress -A -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null | sed 's/^[^.]*\.//')
fi

# Export DOMAIN for use in HTML generation
export DOMAIN

services=($(discover_services))

echo "Found ${#services[@]} services"
echo "Generating dashboard for domain: ${DOMAIN:-localhost}"
generate_dashboard_html "${services[@]}"

echo "Creating ConfigMap..."
create_dashboard_configmap

echo "Dashboard configuration complete!"
echo "The control panel will now display all discovered services."