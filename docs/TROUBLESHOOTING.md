# 🔧 Troubleshooting Guide

## Common Issues and Solutions

### 🚨 Pre-deployment Issues

#### Pre-flight checks fail
```bash
./scripts/preflight-check.sh
```

**Solution**: Address each failed check:
- Install missing software
- Free up disk space
- Ensure ports 80, 443, 6443 are available
- Check Docker daemon is running

#### GitHub OAuth setup confusion
**Problem**: Not sure how to create OAuth App

**Solution**:
1. Go to https://github.com/settings/applications/new
2. Fill in:
   - Application name: `K3s Cluster (yourdomain.com)`
   - Homepage URL: `https://yourdomain.com`
   - Authorization callback URL: `https://yourdomain.com/oauth2/callback`
3. Save and copy Client ID and Secret

### 🌐 DNS Issues

#### Domain not resolving
**Problem**: Services unreachable after deployment

**Check DNS**:
```bash
# Check A record
dig yourdomain.com
dig git.yourdomain.com

# Test resolution
nslookup yourdomain.com
```

**Solution**:
1. Ensure A records point to your server IP
2. Wait 5-10 minutes for DNS propagation
3. Try using a different DNS resolver: `dig @8.8.8.8 yourdomain.com`

### 🔒 Certificate Issues

#### HTTPS not working
**Check certificate status**:
```bash
kubectl get certificate -A
kubectl describe certificate -n <namespace> <cert-name>
```

**Common causes**:
- DNS not properly configured
- Let's Encrypt rate limits
- Firewall blocking HTTP-01 challenge

**Solution**:
```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Force certificate renewal
kubectl delete certificate -n <namespace> <cert-name>
```

### 🐳 Container Issues

#### Pods not starting
**Debug commands**:
```bash
# Check pod status
kubectl get pods -A | grep -v Running

# Describe problematic pod
kubectl describe pod -n <namespace> <pod-name>

# Check logs
kubectl logs -n <namespace> <pod-name>
```

**Common issues**:
- **ImagePullBackOff**: Registry authentication or network issues
- **CrashLoopBackOff**: Application configuration error
- **Pending**: Resource constraints or storage issues

### 🔐 Authentication Issues

#### Can't login to services
**Problem**: GitHub OAuth not working

**Check OAuth proxy**:
```bash
kubectl logs -n auth-system deployment/oauth2-proxy
```

**Verify configuration**:
```bash
# Check environment variables
kubectl get secret -n auth-system oauth2-proxy -o jsonpath='{.data}' | base64 -d

# Test GitHub OAuth
curl -I https://yourdomain.com/oauth2/start
```

### 💾 Storage Issues

#### PVC stuck in Pending
**Check storage classes**:
```bash
kubectl get storageclass
kubectl get pv
kubectl describe pvc -n <namespace> <pvc-name>
```

**Solution**:
- Ensure default storage class exists
- Check node has sufficient disk space
- Verify storage provisioner is running

### 🚀 Service-Specific Issues

#### Gitea not accessible
```bash
# Check Gitea pods
kubectl get pods -n gitea
kubectl logs -n gitea -l app=gitea

# Verify database connection
kubectl exec -n gitea deployment/gitea -- gitea admin user list
```

#### Drone CI builds failing
```bash
# Check Drone server
kubectl logs -n drone deployment/drone-server

# Verify runner
kubectl logs -n drone deployment/drone-runner-kubernetes

# Check secrets
kubectl get secrets -n drone
```

#### ArgoCD sync issues
```bash
# Access ArgoCD CLI
kubectl exec -n argocd deployment/argocd-server -- argocd app list

# Check application status
kubectl exec -n argocd deployment/argocd-server -- argocd app get <app-name>
```

### 🔍 Debugging Tools

#### General cluster health
```bash
# Quick health check
kubectl get nodes
kubectl get pods -A | grep -v Running
kubectl top nodes
kubectl top pods -A

# Check events
kubectl get events -A --sort-by='.lastTimestamp'
```

#### Network connectivity
```bash
# Test internal DNS
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- sh
# Inside the pod:
nslookup kubernetes.default
curl http://gitea.gitea.svc.cluster.local:3000
```

#### Log aggregation
```bash
# View all logs for a namespace
kubectl logs -n <namespace> -l <label-selector> --tail=100 -f

# Export logs
kubectl logs -n <namespace> deployment/<deployment> > logs.txt
```

### 🆘 Recovery Procedures

#### Restart a service
```bash
# Restart deployment
kubectl rollout restart deployment -n <namespace> <deployment>

# Force pod recreation
kubectl delete pod -n <namespace> <pod-name>
```

#### Reset component
```bash
# Reinstall a component
./bootstrap.sh --components <component-name>
```

#### Emergency access
```bash
# Port forward to access service directly
kubectl port-forward -n <namespace> svc/<service> 8080:80

# Access via localhost:8080
```

### 📞 Getting More Help

1. **Check logs**: Always check pod logs first
   ```bash
   kubectl logs -n <namespace> <pod> --previous
   ```

2. **Enable debug logging**:
   ```bash
   kubectl set env deployment/<deployment> -n <namespace> DEBUG=true
   ```

3. **Community resources**:
   - K3s Documentation: https://docs.k3s.io
   - Kubernetes Slack: https://kubernetes.slack.com
   - GitHub Issues: Report bugs with full logs

4. **Collect diagnostic info**:
   ```bash
   # Generate support bundle
   kubectl cluster-info dump > cluster-dump.tar
   ```

### 🔄 Common Fixes

#### "It was working yesterday"
1. Check if certificates expired
2. Verify external dependencies (GitHub, DNS)
3. Review recent changes in git log
4. Check disk space on nodes

#### Performance issues
1. Check resource usage: `kubectl top nodes`
2. Review pod resource limits
3. Check for memory leaks in pods
4. Verify storage performance

#### After system reboot
1. Ensure K3s started: `sudo systemctl status k3s`
2. Check all pods are running
3. Verify load balancer has correct IP
4. Test ingress routing

Remember: Most issues can be resolved by checking logs and ensuring proper configuration!