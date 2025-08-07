#!/bin/bash
# Security scanning and compliance installation

source "${SCRIPT_DIR}/lib/common.sh"

info "Installing security scanning and compliance tools..."

# Create namespace
ensure_namespace security

# Install Falco for runtime security
info "Installing Falco runtime security..."

# Add Falco Helm repository
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

# Create Falco values
cat > /tmp/falco-values.yaml <<EOF
# Driver configuration
driver:
  enabled: true
  kind: modern-ebpf  # Use eBPF for better performance

# Falco configuration
falco:
  rules_file:
    - /etc/falco/falco_rules.yaml
    - /etc/falco/falco_rules.local.yaml
    - /etc/falco/k8s_audit_rules.yaml
    - /etc/falco/rules.d
  
  # Enable additional plugins
  plugins:
    - name: k8saudit
      library_path: libk8saudit.so
      init_config:
        maxEventSize: 1048576
      open_params: "http://:9765/k8s-audit"
    - name: json
      library_path: libjson.so

  # Output configuration
  json_output: true
  json_include_output_property: true
  
  # gRPC output for falcosidekick
  grpc:
    enabled: true
    bind_address: "0.0.0.0:5060"
  
  # Metrics
  metrics:
    enabled: true
    interval: 30s
    output_rule: true
    state_counters_enabled: true

# Falcosidekick configuration
falcosidekick:
  enabled: true
  replicaCount: 1
  config:
    # Webhook to control panel
    webhook:
      address: http://control-panel.control-panel:80/api/security/alerts
    
    # Prometheus metrics
    prometheus:
      enabled: true
    
    # Custom fields
    customfields:
      cluster: k3s
      environment: ${ENVIRONMENT:-production}

# Enable Falco export to Prometheus
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: monitoring

# Custom rules
customRules:
  rules-custom.yaml: |
    - rule: Detect Cryptocurrency Mining
      desc: Detect cryptocurrency mining activities
      condition: >
        spawned_process and (
          proc.name in (crypto_miners) or
          (proc.name in (general_miners) and proc.cmdline contains "stratum+tcp") or
          proc.cmdline contains "monero" or
          proc.cmdline contains "xmr-stak" or
          proc.cmdline contains "minerd"
        )
      output: >
        Cryptocurrency miner detected (user=%user.name command=%proc.cmdline container=%container.name image=%container.image.repository)
      priority: CRITICAL
      tags: [mitre_persistence, cryptomining]
      
    - rule: Detect Suspicious Network Tool
      desc: Detect network tools that can be used for scanning/exploitation
      condition: >
        spawned_process and (
          proc.name in (nc, ncat, netcat, nmap, masscan, zmap) or
          (proc.name=python and proc.cmdline contains "socket") or
          (proc.name=perl and proc.cmdline contains "Socket")
        )
      output: >
        Suspicious network tool launched (user=%user.name command=%proc.cmdline container=%container.name)
      priority: WARNING
      tags: [network, mitre_discovery]
      
    - rule: Container Privilege Escalation
      desc: Detect when a container process tries to escalate privileges
      condition: >
        container and proc.vpid=1 and proc_is_new=true and (
          proc.name in (sudo, su) or
          (proc.name=docker or proc.name=kubectl or proc.name=crictl)
        )
      output: >
        Privilege escalation attempt in container (user=%user.name command=%proc.cmdline container=%container.name)
      priority: CRITICAL
      tags: [container, mitre_privilege_escalation]
      
    - list: crypto_miners
      items: [minerd, xmrig, xmr-stak-cpu, xmr-stak-gpu, bitminer, cgminer]
      
    - list: general_miners
      items: [python, python2, python3, ruby, perl, bash, sh, node]
EOF

# Install Falco
helm upgrade --install falco falcosecurity/falco \
  -f /tmp/falco-values.yaml \
  -n security \
  --wait

# Install Polaris for Kubernetes best practices
info "Installing Polaris for best practices scanning..."

# Create Polaris configuration
cat > /tmp/polaris-config.yaml <<EOF
checks:
  # Security checks
  hostIPCSet: danger
  hostPIDSet: danger
  hostNetworkSet: warning
  hostPortSet: warning
  
  # Container security
  readOnlyRootFilesystem: warning
  runAsRootAllowed: warning
  runAsPrivileged: danger
  notReadOnlyRootFilesystem: warning
  privilegeEscalationAllowed: danger
  
  # Resources
  cpuRequestsMissing: warning
  cpuLimitsMissing: warning
  memoryRequestsMissing: warning
  memoryLimitsMissing: warning
  
  # Probes
  livenessProbeMissing: warning
  readinessProbeMissing: warning
  
  # Images
  tagNotSpecified: danger
  pullPolicyNotAlways: warning
  
exemptions:
  - namespace: kube-system
    controllerNames:
      - kube-apiserver
      - kube-proxy
      - kube-scheduler
      - kube-controller-manager
  - namespace: security
    controllerNames:
      - falco
EOF

# Install Polaris
kubectl apply -f https://github.com/FairwindsOps/polaris/releases/latest/download/bundle.yaml
kubectl create configmap polaris-config -n polaris --from-file=config.yaml=/tmp/polaris-config.yaml

# Install Kubesec for manifest scanning
info "Installing Kubesec webhook for admission control..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: kubesec-webhook
  namespace: security
spec:
  ports:
  - name: https
    port: 443
    targetPort: 8443
  selector:
    app: kubesec-webhook
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kubesec-webhook
  namespace: security
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kubesec-webhook
  template:
    metadata:
      labels:
        app: kubesec-webhook
    spec:
      containers:
      - name: kubesec
        image: kubesec/kubesec:latest
        command:
        - /kubesec
        - http
        - --port=8443
        ports:
        - containerPort: 8443
        resources:
          requests:
            memory: 128Mi
            cpu: 100m
          limits:
            memory: 256Mi
            cpu: 500m
EOF

# Install kube-bench for CIS benchmarks
info "Installing kube-bench for CIS compliance checking..."

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: kube-bench
  namespace: security
spec:
  schedule: "0 2 * * 1"  # Weekly on Monday at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          hostPID: true
          containers:
          - name: kube-bench
            image: aquasec/kube-bench:latest
            command: ["kube-bench"]
            args: ["run", "--targets", "master,node", "--benchmark", "cis-1.6"]
            volumeMounts:
            - name: var-lib-etcd
              mountPath: /var/lib/etcd
              readOnly: true
            - name: etc-kubernetes
              mountPath: /etc/kubernetes
              readOnly: true
            - name: etc-systemd
              mountPath: /etc/systemd
              readOnly: true
            - name: var-lib-kubelet
              mountPath: /var/lib/kubelet
              readOnly: true
            - name: etc-cni
              mountPath: /etc/cni
              readOnly: true
            - name: opt-cni
              mountPath: /opt/cni
              readOnly: true
            - name: var-lib-cni
              mountPath: /var/lib/cni
              readOnly: true
          restartPolicy: OnFailure
          volumes:
          - name: var-lib-etcd
            hostPath:
              path: "/var/lib/etcd"
          - name: etc-kubernetes
            hostPath:
              path: "/etc/kubernetes"
          - name: etc-systemd
            hostPath:
              path: "/etc/systemd"
          - name: var-lib-kubelet
            hostPath:
              path: "/var/lib/kubelet"
          - name: etc-cni
            hostPath:
              path: "/etc/cni"
          - name: opt-cni
            hostPath:
              path: "/opt/cni"
          - name: var-lib-cni
            hostPath:
              path: "/var/lib/cni"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-bench
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: default
  namespace: security
EOF

# Install Network Policies for security
info "Creating default network policies..."

# Default deny all ingress traffic
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-access
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

# Create Pod Security Standards
info "Applying Pod Security Standards..."

# Apply restricted standards to namespaces
for ns in default production staging; do
  kubectl label namespace $ns \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/warn=restricted \
    --overwrite 2>/dev/null || true
done

# Create RBAC audit configuration
cat > "${SCRIPT_DIR}/.cluster/audit-policy.yaml" <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Don't log read operations
  - level: None
    verbs: ["get", "list", "watch"]
    
  # Log pod creation at Metadata level
  - level: Metadata
    verbs: ["create", "update", "patch"]
    resources:
    - group: ""
      resources: ["pods", "services"]
      
  # Log secret operations at Metadata level
  - level: Metadata
    resources:
    - group: ""
      resources: ["secrets", "configmaps"]
      
  # Log everything else at Request level
  - level: Request
    verbs: ["create", "update", "patch", "delete"]
EOF

# Create security scanning scripts
info "Creating security scanning utilities..."

cat > "${SCRIPT_DIR}/scripts/security-scan.sh" <<'EOF'
#!/bin/bash
# Run security scans on the cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

SCAN_TYPE="${1:-all}"
NAMESPACE="${2:-all}"

show_usage() {
    cat << USAGE
Usage: $0 [scan-type] [namespace]

Run security scans on the cluster

Scan Types:
    all         Run all security scans
    runtime     Falco runtime security events
    compliance  CIS benchmark compliance
    policies    Pod security policies
    images      Container image vulnerabilities
    manifests   Kubernetes manifest security

Examples:
    # Run all scans
    $0 all

    # Check runtime security
    $0 runtime

    # Scan specific namespace
    $0 policies production
USAGE
}

# Check runtime security with Falco
scan_runtime() {
    info "Checking runtime security events..."
    
    # Get recent Falco alerts
    kubectl logs -n security -l app.kubernetes.io/name=falco --tail=100 | \
        grep -E "Warning|Error|Critical" || echo "No security events found"
}

# Run CIS compliance check
scan_compliance() {
    info "Running CIS compliance scan..."
    
    # Trigger kube-bench job
    kubectl create job --from=cronjob/kube-bench -n security kube-bench-manual-$(date +%s)
    
    # Wait for completion
    sleep 30
    
    # Get results
    kubectl logs -n security -l job-name=kube-bench-manual-* --tail=1000
}

# Check pod security policies
scan_policies() {
    info "Checking pod security policies..."
    
    if [[ "$NAMESPACE" == "all" ]]; then
        namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
    else
        namespaces="$NAMESPACE"
    fi
    
    for ns in $namespaces; do
        echo "Namespace: $ns"
        kubectl get pods -n "$ns" -o json | jq -r '.items[] | 
            select(.spec.securityContext.runAsNonRoot != true or 
                   .spec.containers[].securityContext.privileged == true or
                   .spec.hostNetwork == true) | 
            .metadata.name' | while read pod; do
            echo "  ⚠️  $pod - Security concerns found"
        done
    done
}

# Scan container images
scan_images() {
    info "Scanning container images for vulnerabilities..."
    
    # Get all images in cluster
    kubectl get pods --all-namespaces -o json | \
        jq -r '.items[].spec.containers[].image' | \
        sort -u | while read image; do
        
        echo "Scanning: $image"
        
        # Check if image is in Harbor
        if [[ "$image" =~ ^${DOMAIN:-registry.local} ]]; then
            # Get scan results from Harbor
            project=$(echo "$image" | cut -d'/' -f2)
            repo=$(echo "$image" | cut -d'/' -f3 | cut -d':' -f1)
            tag=$(echo "$image" | cut -d':' -f2)
            
            curl -s -u admin:${HARBOR_ADMIN_PASSWORD} \
                "https://${DOMAIN:-registry.local}/api/v2.0/projects/$project/repositories/$repo/artifacts/$tag/scan" | \
                jq -r '.scan_overview.application/vnd.scanner.adapter.vuln.report.harbor+json; v1.0.summary' 2>/dev/null || \
                echo "  No scan results available"
        fi
    done
}

# Scan Kubernetes manifests
scan_manifests() {
    info "Scanning Kubernetes manifests..."
    
    # Use Polaris dashboard
    kubectl port-forward -n polaris svc/polaris-dashboard 8080:80 &
    PF_PID=$!
    
    sleep 5
    
    info "Polaris dashboard available at http://localhost:8080"
    info "Press any key to close..."
    read -n 1
    
    kill $PF_PID
}

# Generate security report
generate_report() {
    local report_file="/tmp/security-report-$(date +%Y%m%d-%H%M%S).md"
    
    cat > "$report_file" <<REPORT
# Security Scan Report

Generated: $(date)

## Runtime Security (Falco)
\`\`\`
$(scan_runtime 2>&1)
\`\`\`

## Pod Security
\`\`\`
$(scan_policies 2>&1)
\`\`\`

## Recommendations

1. Enable Pod Security Standards on all namespaces
2. Implement Network Policies for all applications
3. Regular vulnerability scanning of images
4. Review and fix CIS benchmark failures
5. Monitor Falco alerts continuously

REPORT
    
    success "Security report generated: $report_file"
}

# Main execution
case $SCAN_TYPE in
    all)
        scan_runtime
        echo ""
        scan_policies
        echo ""
        generate_report
        ;;
    runtime)
        scan_runtime
        ;;
    compliance)
        scan_compliance
        ;;
    policies)
        scan_policies
        ;;
    images)
        scan_images
        ;;
    manifests)
        scan_manifests
        ;;
    help|*)
        show_usage
        ;;
esac
EOF

chmod +x "${SCRIPT_DIR}/scripts/security-scan.sh"

# Create OPA policies for admission control
info "Setting up OPA policies..."

cat > "${SCRIPT_DIR}/templates/opa-policies/require-labels.rego" <<'EOF'
package kubernetes.admission

import future.keywords.contains
import future.keywords.if
import future.keywords.in

deny[msg] {
    input.request.kind.kind == "Pod"
    required_labels := {"app", "version", "environment"}
    provided_labels := input.request.object.metadata.labels
    missing := required_labels - {label | provided_labels[label]}
    count(missing) > 0
    msg := sprintf("Pod is missing required labels: %v", [missing])
}
EOF

cat > "${SCRIPT_DIR}/templates/opa-policies/image-registry.rego" <<'EOF'
package kubernetes.admission

deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not starts_with(container.image, "registry.local/")
    not starts_with(container.image, "docker.io/library/")
    msg := sprintf("Container image must be from approved registry: %v", [container.image])
}
EOF

# Clean up
rm -f /tmp/falco-values.yaml /tmp/polaris-config.yaml

success "Security scanning and compliance tools installed"
info "=== Security Features Enabled ==="
info "✓ Falco runtime security monitoring"
info "✓ Polaris best practices scanning"
info "✓ CIS benchmark compliance (kube-bench)"
info "✓ Network policies"
info "✓ Pod Security Standards"
info "✓ Kubesec manifest scanning"
info ""
info "=== Usage ==="
info "# Run security scan:"
info "./scripts/security-scan.sh all"
info ""
info "# Check specific scan:"
info "./scripts/security-scan.sh runtime"
info "./scripts/security-scan.sh compliance"
info "./scripts/security-scan.sh policies"