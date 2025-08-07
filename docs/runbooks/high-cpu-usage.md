# Runbook: High CPU Usage Alert

## Alert Details
- **Alert Name**: NodeHighCPU
- **Severity**: Warning
- **Threshold**: CPU usage > 85% for 10 minutes

## Impact
High CPU usage can lead to:
- Slow application response times
- Pod scheduling failures
- System instability

## Investigation Steps

1. **Identify the affected node**
   ```bash
   kubectl top nodes
   ```

2. **Check pod resource usage on the node**
   ```bash
   kubectl top pods --all-namespaces --field-selector spec.nodeName=<node-name>
   ```

3. **Look for CPU-intensive processes**
   ```bash
   kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name> \
     -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,CPU:.spec.containers[*].resources.requests.cpu
   ```

4. **Check for recent deployments**
   ```bash
   kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i deploy
   ```

## Resolution Steps

### Immediate Actions

1. **If a specific pod is consuming excessive CPU:**
   ```bash
   # Check pod logs
   kubectl logs -n <namespace> <pod-name>
   
   # Consider restarting the pod
   kubectl delete pod -n <namespace> <pod-name>
   ```

2. **If the node is overloaded:**
   ```bash
   # Cordon the node to prevent new pods
   kubectl cordon <node-name>
   
   # Drain non-critical pods
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
   ```

3. **Scale up the cluster if needed:**
   ```bash
   # Check scaling recommendation
   ./scripts/cluster-scale.sh check
   
   # Add a new node if recommended
   ./scripts/cluster-scale.sh scale-up
   ```

### Long-term Solutions

1. **Set resource limits for pods**
   ```yaml
   resources:
     limits:
       cpu: "1000m"
     requests:
       cpu: "100m"
   ```

2. **Enable Horizontal Pod Autoscaling (HPA)**
   ```bash
   kubectl autoscale deployment <deployment-name> --cpu-percent=70 --min=2 --max=10
   ```

3. **Review and optimize application code**
   - Profile CPU usage
   - Optimize algorithms
   - Add caching where appropriate

## Monitoring

After resolution, monitor:
- CPU usage trend in Grafana
- Application performance metrics
- Pod restart counts

## Prevention

1. Always set resource requests and limits
2. Use HPA for variable workloads
3. Regular capacity planning reviews
4. Load testing before production deployment