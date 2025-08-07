# Runbook: Pod Crash Loop Alert

## Alert Details
- **Alert Name**: KubernetesPodCrashLooping
- **Severity**: Critical
- **Threshold**: Pod restarting more than 0 times per minute

## Impact
- Service unavailability
- Resource waste from constant restarts
- Potential data loss

## Investigation Steps

1. **Identify the crashing pod**
   ```bash
   kubectl get pods --all-namespaces | grep -E "CrashLoopBackOff|Error|Restarting"
   ```

2. **Check pod events**
   ```bash
   kubectl describe pod -n <namespace> <pod-name>
   ```

3. **Review pod logs**
   ```bash
   # Current logs
   kubectl logs -n <namespace> <pod-name>
   
   # Previous instance logs
   kubectl logs -n <namespace> <pod-name> --previous
   
   # All containers in pod
   kubectl logs -n <namespace> <pod-name> --all-containers=true
   ```

4. **Check resource limits**
   ```bash
   kubectl get pod -n <namespace> <pod-name> -o yaml | grep -A 10 resources:
   ```

## Common Causes & Solutions

### 1. Application Error
**Symptoms**: Error messages in logs, exit code 1
```bash
# Fix application code and redeploy
kubectl set image deployment/<deployment> <container>=<new-image> -n <namespace>
```

### 2. Out of Memory (OOMKilled)
**Symptoms**: Exit code 137, OOMKilled in events
```bash
# Increase memory limits
kubectl patch deployment <deployment> -n <namespace> --patch '
spec:
  template:
    spec:
      containers:
      - name: <container>
        resources:
          limits:
            memory: "1Gi"
          requests:
            memory: "512Mi"
'
```

### 3. Missing ConfigMap/Secret
**Symptoms**: "configmap not found" or "secret not found" in events
```bash
# List and verify ConfigMaps/Secrets
kubectl get configmap,secret -n <namespace>

# Create missing resource or fix reference
```

### 4. Liveness Probe Failure
**Symptoms**: "Liveness probe failed" in events
```bash
# Temporarily disable probe to debug
kubectl patch deployment <deployment> -n <namespace> --type json -p='[
  {"op": "remove", "path": "/spec/template/spec/containers/0/livenessProbe"}
]'
```

### 5. Image Pull Error
**Symptoms**: "ErrImagePull" or "ImagePullBackOff"
```bash
# Check image name and registry credentials
kubectl get pod -n <namespace> <pod-name> -o yaml | grep image:
kubectl get secrets -n <namespace> | grep docker
```

## Resolution Steps

1. **Quick fix - Delete pod to force recreation**
   ```bash
   kubectl delete pod -n <namespace> <pod-name>
   ```

2. **Scale down and up**
   ```bash
   kubectl scale deployment <deployment> -n <namespace> --replicas=0
   kubectl scale deployment <deployment> -n <namespace> --replicas=<original-count>
   ```

3. **Rollback to previous version**
   ```bash
   kubectl rollout undo deployment/<deployment> -n <namespace>
   ```

## Post-Resolution

1. **Verify pod stability**
   ```bash
   kubectl get pod -n <namespace> <pod-name> -w
   ```

2. **Check application functionality**
   - Test endpoints
   - Verify logs are clean
   - Monitor metrics

3. **Document root cause**
   - Update runbooks
   - Create post-mortem if needed

## Prevention

1. **Implement proper health checks**
   ```yaml
   livenessProbe:
     httpGet:
       path: /health
       port: 8080
     initialDelaySeconds: 30
     periodSeconds: 10
   readinessProbe:
     httpGet:
       path: /ready
       port: 8080
     initialDelaySeconds: 5
     periodSeconds: 5
   ```

2. **Set appropriate resource limits**
3. **Use init containers for dependencies**
4. **Implement graceful shutdown**
5. **Test in staging environment first**