#!/bin/bash
# Cluster state management for resumable bootstrap

# State file location
export STATE_FILE="${SCRIPT_DIR:-.}/.cluster/state.json"
export STATE_DIR="${SCRIPT_DIR:-.}/.cluster"

# Initialize state directory
init_state() {
    mkdir -p "$STATE_DIR"
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"components": {}, "environment": {}, "metadata": {}}' > "$STATE_FILE"
    fi
}

# Save component state
save_component_state() {
    local component=$1
    local status=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    init_state
    
    # Use jq if available, otherwise use sed
    if command -v jq >/dev/null 2>&1; then
        jq --arg comp "$component" --arg stat "$status" --arg ts "$timestamp" \
            '.components[$comp] = {"status": $stat, "timestamp": $ts}' \
            "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
        # Fallback to simple tracking
        echo "${component}:${status}:${timestamp}" >> "${STATE_DIR}/components.log"
    fi
}

# Get component state
get_component_state() {
    local component=$1
    
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "not_started"
        return
    fi
    
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg comp "$component" '.components[$comp].status // "not_started"' "$STATE_FILE"
    else
        # Fallback to simple tracking
        grep "^${component}:" "${STATE_DIR}/components.log" 2>/dev/null | tail -1 | cut -d: -f2 || echo "not_started"
    fi
}

# Save environment config
save_environment_config() {
    init_state
    
    cat > "${STATE_DIR}/environment.conf" <<EOF
ENVIRONMENT=${ENVIRONMENT}
DOMAIN=${DOMAIN}
KUBECONFIG=${KUBECONFIG}
STORAGE_CLASS=${STORAGE_CLASS:-longhorn}
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@${DOMAIN}}
NODE_TYPE=${NODE_TYPE:-master}
CLUSTER_NAME=${CLUSTER_NAME:-k3s-cluster}
EOF
}

# Load environment config
load_environment_config() {
    if [[ -f "${STATE_DIR}/environment.conf" ]]; then
        source "${STATE_DIR}/environment.conf"
    fi
}

# Check if component is installed
is_component_installed() {
    local component=$1
    local state=$(get_component_state "$component")
    [[ "$state" == "completed" ]]
}

# List installed components
list_installed_components() {
    if command -v jq >/dev/null 2>&1 && [[ -f "$STATE_FILE" ]]; then
        jq -r '.components | to_entries[] | select(.value.status == "completed") | .key' "$STATE_FILE"
    elif [[ -f "${STATE_DIR}/components.log" ]]; then
        grep ":completed:" "${STATE_DIR}/components.log" | cut -d: -f1 | sort -u
    fi
}

# Save credentials
save_credentials() {
    local service=$1
    local content=$2
    
    mkdir -p "${STATE_DIR}/credentials"
    echo "$content" > "${STATE_DIR}/credentials/${service}.conf"
    chmod 600 "${STATE_DIR}/credentials/${service}.conf"
}

# Get credentials
get_credentials() {
    local service=$1
    local cred_file="${STATE_DIR}/credentials/${service}.conf"
    
    if [[ -f "$cred_file" ]]; then
        cat "$cred_file"
    fi
}

# Mark bootstrap phase
mark_bootstrap_phase() {
    local phase=$1
    echo "$phase" > "${STATE_DIR}/bootstrap.phase"
}

# Get bootstrap phase
get_bootstrap_phase() {
    if [[ -f "${STATE_DIR}/bootstrap.phase" ]]; then
        cat "${STATE_DIR}/bootstrap.phase"
    else
        echo "not_started"
    fi
}

# Export functions
export -f init_state save_component_state get_component_state is_component_installed
export -f list_installed_components save_credentials get_credentials
export -f save_environment_config load_environment_config
export -f mark_bootstrap_phase get_bootstrap_phase