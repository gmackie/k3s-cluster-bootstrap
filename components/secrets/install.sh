#!/bin/bash
# Secrets management installation with Sealed Secrets

source "${SCRIPT_DIR}/lib/common.sh"

info "Installing Sealed Secrets for secrets management..."

# Create namespace
ensure_namespace sealed-secrets

# Install Sealed Secrets controller
info "Installing Sealed Secrets controller..."

# Get latest version
SEALED_SECRETS_VERSION="v0.24.5"

# Install the controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml

# Wait for controller to be ready
wait_for_deployment kube-system sealed-secrets-controller

# Download kubeseal CLI if not present
if ! command_exists kubeseal; then
    info "Downloading kubeseal CLI..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if [[ $(uname -m) == "arm64" ]]; then
            curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/kubeseal-${SEALED_SECRETS_VERSION#v}-darwin-arm64.tar.gz | tar xz
        else
            curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/kubeseal-${SEALED_SECRETS_VERSION#v}-darwin-amd64.tar.gz | tar xz
        fi
    else
        # Linux
        curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/kubeseal-${SEALED_SECRETS_VERSION#v}-linux-amd64.tar.gz | tar xz
    fi
    
    sudo mv kubeseal /usr/local/bin/
    rm -f README.md LICENSE
fi

# Get the public certificate for sealing secrets
info "Fetching Sealed Secrets public certificate..."
kubeseal --fetch-cert \
    --controller-name=sealed-secrets-controller \
    --controller-namespace=kube-system \
    > "${SCRIPT_DIR}/.cluster/sealed-secrets-pub.pem"

# Create example sealed secrets
info "Creating example sealed secrets..."

# Example: Database credentials
cat > /tmp/db-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: default
type: Opaque
data:
  username: $(echo -n "dbuser" | base64)
  password: $(echo -n "$(generate_password)" | base64)
EOF

# Seal the secret
kubeseal --cert "${SCRIPT_DIR}/.cluster/sealed-secrets-pub.pem" \
    -f /tmp/db-secret.yaml \
    -o yaml > /tmp/sealed-db-secret.yaml

# Create secrets management scripts
info "Creating secrets management utilities..."

# Create seal-secret script
cat > "${SCRIPT_DIR}/scripts/seal-secret.sh" <<'EOF'
#!/bin/bash
# Seal a Kubernetes secret

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

SECRET_FILE="${1:-}"
OUTPUT_FILE="${2:-}"

show_usage() {
    cat << USAGE
Usage: $0 <secret-file> [output-file]

Seal a Kubernetes secret for safe storage in Git

Arguments:
    secret-file    Path to the secret YAML file
    output-file    Path for sealed secret output (optional)

Examples:
    # Seal a secret
    $0 my-secret.yaml

    # Seal with custom output
    $0 my-secret.yaml sealed-my-secret.yaml

    # Create and seal in one command
    kubectl create secret generic my-secret --from-literal=key=value --dry-run=client -o yaml | $0 -
USAGE
}

if [[ -z "$SECRET_FILE" || "$SECRET_FILE" == "--help" || "$SECRET_FILE" == "-h" ]]; then
    show_usage
    exit 0
fi

# Check for public certificate
CERT_FILE="${SCRIPT_DIR}/../.cluster/sealed-secrets-pub.pem"
if [[ ! -f "$CERT_FILE" ]]; then
    error "Sealed Secrets certificate not found. Run the secrets component installation first."
fi

# Determine output file
if [[ -z "$OUTPUT_FILE" ]]; then
    if [[ "$SECRET_FILE" == "-" ]]; then
        OUTPUT_FILE="-"
    else
        OUTPUT_FILE="${SECRET_FILE%.yaml}-sealed.yaml"
    fi
fi

# Seal the secret
info "Sealing secret..."
if [[ "$SECRET_FILE" == "-" ]]; then
    # Read from stdin
    kubeseal --cert "$CERT_FILE" -o yaml
else
    # Read from file
    kubeseal --cert "$CERT_FILE" -f "$SECRET_FILE" -o yaml > "$OUTPUT_FILE"
    success "Sealed secret created: $OUTPUT_FILE"
fi
EOF

chmod +x "${SCRIPT_DIR}/scripts/seal-secret.sh"

# Create manage-secrets script
cat > "${SCRIPT_DIR}/scripts/manage-secrets.sh" <<'EOF'
#!/bin/bash
# Manage cluster secrets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

ACTION="${1:-help}"
shift || true

show_usage() {
    cat << USAGE
Usage: $0 [action] [options]

Manage Kubernetes secrets securely

Actions:
    create      Create a new sealed secret
    list        List all secrets in cluster
    backup      Backup master key
    rotate      Rotate encryption keys
    validate    Validate sealed secrets

Examples:
    # Create a new secret
    $0 create app-secret --from-literal=api-key=12345

    # List all secrets
    $0 list --all-namespaces

    # Backup master key
    $0 backup /secure/location/

    # Validate sealed secrets
    $0 validate my-sealed-secret.yaml
USAGE
}

create_secret() {
    local name="${1:-}"
    shift || true
    
    if [[ -z "$name" ]]; then
        error "Secret name required"
    fi
    
    # Create the secret
    kubectl create secret generic "$name" "$@" --dry-run=client -o yaml > /tmp/secret.yaml
    
    # Seal it
    "${SCRIPT_DIR}/seal-secret.sh" /tmp/secret.yaml
    
    # Clean up
    rm -f /tmp/secret.yaml
}

list_secrets() {
    info "Listing secrets..."
    kubectl get secrets "$@"
    
    echo ""
    info "Sealed secrets:"
    kubectl get sealedsecrets --all-namespaces 2>/dev/null || echo "No sealed secrets found"
}

backup_key() {
    local backup_dir="${1:-}"
    
    if [[ -z "$backup_dir" ]]; then
        error "Backup directory required"
    fi
    
    info "Backing up Sealed Secrets master key..."
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Get the master key
    kubectl get secret -n kube-system sealed-secrets-key -o yaml > "$backup_dir/sealed-secrets-key.yaml"
    
    # Get the public certificate
    cp "${SCRIPT_DIR}/../.cluster/sealed-secrets-pub.pem" "$backup_dir/"
    
    # Create restore instructions
    cat > "$backup_dir/RESTORE_INSTRUCTIONS.md" << INSTRUCTIONS
# Sealed Secrets Key Restore Instructions

To restore the Sealed Secrets master key:

1. Apply the key to the new cluster:
   \`\`\`
   kubectl apply -f sealed-secrets-key.yaml
   \`\`\`

2. Delete the controller pod to pick up the key:
   \`\`\`
   kubectl delete pod -n kube-system -l name=sealed-secrets-controller
   \`\`\`

3. Verify the key is loaded:
   \`\`\`
   kubectl logs -n kube-system -l name=sealed-secrets-controller
   \`\`\`

**IMPORTANT**: Keep this backup secure! Anyone with this key can decrypt all sealed secrets.
INSTRUCTIONS
    
    success "Master key backed up to: $backup_dir"
    warn "Keep this backup secure and encrypted!"
}

validate_secret() {
    local file="${1:-}"
    
    if [[ -z "$file" ]]; then
        error "Sealed secret file required"
    fi
    
    info "Validating sealed secret: $file"
    
    # Check if it's a valid YAML
    if ! kubectl apply --dry-run=client -f "$file" >/dev/null 2>&1; then
        error "Invalid YAML file"
    fi
    
    # Check if it's a SealedSecret
    if ! grep -q "kind: SealedSecret" "$file"; then
        error "Not a SealedSecret resource"
    fi
    
    success "Sealed secret is valid"
}

# Main execution
case $ACTION in
    create)
        create_secret "$@"
        ;;
    list)
        list_secrets "$@"
        ;;
    backup)
        backup_key "$@"
        ;;
    validate)
        validate_secret "$@"
        ;;
    help|*)
        show_usage
        ;;
esac
EOF

chmod +x "${SCRIPT_DIR}/scripts/manage-secrets.sh"

# Create secret templates
info "Creating secret templates..."

mkdir -p "${SCRIPT_DIR}/templates/secrets"

# Registry credentials template
cat > "${SCRIPT_DIR}/templates/secrets/registry-creds.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: registry-credentials
  namespace: default
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: |
    {
      "auths": {
        "${DOMAIN:-registry.local}": {
          "username": "admin",
          "password": "CHANGE_ME",
          "auth": "BASE64_ENCODED_USERNAME:PASSWORD"
        }
      }
    }
EOF

# Database credentials template
cat > "${SCRIPT_DIR}/templates/secrets/database-creds.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: default
type: Opaque
stringData:
  username: dbuser
  password: CHANGE_ME
  host: postgres.database.svc.cluster.local
  port: "5432"
  database: myapp
EOF

# API keys template
cat > "${SCRIPT_DIR}/templates/secrets/api-keys.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: api-keys
  namespace: default
type: Opaque
stringData:
  github-token: CHANGE_ME
  slack-webhook: CHANGE_ME
  smtp-password: CHANGE_ME
EOF

# TLS certificate template
cat > "${SCRIPT_DIR}/templates/secrets/tls-cert.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: tls-certificate
  namespace: default
type: kubernetes.io/tls
data:
  tls.crt: |
    -----BEGIN CERTIFICATE-----
    CHANGE_ME
    -----END CERTIFICATE-----
  tls.key: |
    -----BEGIN PRIVATE KEY-----
    CHANGE_ME
    -----END PRIVATE KEY-----
EOF

# Create ServiceMonitor for monitoring
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: sealed-secrets-controller
  namespace: kube-system
  labels:
    app.kubernetes.io/name: sealed-secrets
spec:
  selector:
    matchLabels:
      name: sealed-secrets-controller
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
EOF

# Clean up
rm -f /tmp/db-secret.yaml /tmp/sealed-db-secret.yaml

success "Sealed Secrets installed successfully"
info "=== Sealed Secrets Information ==="
info "Public certificate saved to: .cluster/sealed-secrets-pub.pem"
info ""
info "=== Usage Examples ==="
info "# Seal a secret:"
info "./scripts/seal-secret.sh my-secret.yaml"
info ""
info "# Create and seal a secret:"
info "./scripts/manage-secrets.sh create my-secret --from-literal=key=value"
info ""
info "# Backup master key (IMPORTANT!):"
info "./scripts/manage-secrets.sh backup /secure/backup/location/"
info ""
info "=== Features ==="
info "✓ Encrypted secrets safe for Git storage"
info "✓ One-way encryption (only cluster can decrypt)"
info "✓ Automatic key rotation support"
info "✓ kubectl compatible workflow"
info "✓ No external dependencies"