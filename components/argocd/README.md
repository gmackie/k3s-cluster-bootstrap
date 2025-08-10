# ArgoCD Component

This component installs ArgoCD, a declarative GitOps continuous delivery tool for Kubernetes.

## Features

- **GitOps**: Declarative application deployment from Git
- **Multi-Cluster**: Manage applications across multiple clusters
- **Automated Sync**: Auto-sync when Git changes are detected
- **Rollback**: Easy rollback to any previous state
- **RBAC**: Fine-grained access control with SSO
- **Webhooks**: GitHub/GitLab webhook integration
- **Multi-Tenancy**: Projects for team isolation
- **ApplicationSets**: Template applications across environments

## Architecture

- **Server**: API/UI server
- **Repo Server**: Git repository cache
- **Application Controller**: Monitors and syncs applications
- **Redis**: Caching layer
- **Dex**: OpenID Connect provider
- **ApplicationSet Controller**: Manages ApplicationSets
- **Notifications Controller**: Sends notifications

## Access

- **Web UI**: `https://argocd.<domain>`
- **gRPC API**: `https://argocd-grpc.<domain>`
- **Admin User**: `admin`
- **Admin Password**: See credentials file

## Quick Start

### 1. Login to UI
```
URL: https://argocd.<domain>
Username: admin
Password: <from credentials file>
```

### 2. Add Git Repository

#### Via UI:
1. Settings → Repositories
2. Connect Repo using HTTPS/SSH
3. Add credentials if private

#### Via CLI:
```bash
argocd repo add https://github.com/myorg/myrepo.git --username git --password <token>
```

### 3. Create First Application

#### Via UI:
1. Applications → New App
2. Fill in:
   - Application Name: `my-app`
   - Project: `default`
   - Repository URL: Your repo
   - Path: `k8s/` or `helm/`
   - Cluster: `https://kubernetes.default.svc`
   - Namespace: `default`

#### Via CLI:
```bash
argocd app create my-app \
  --repo https://github.com/myorg/myrepo.git \
  --path k8s \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default
```

### 4. Sync Application
```bash
# Manual sync
argocd app sync my-app

# Enable auto-sync
argocd app set my-app --sync-policy automated
```

## GitOps Repository Structure

### Recommended Structure
```
my-gitops-repo/
├── apps/                    # Application definitions
│   ├── app1/
│   │   ├── base/           # Base manifests
│   │   ├── overlays/       # Environment overrides
│   │   │   ├── dev/
│   │   │   ├── staging/
│   │   │   └── prod/
│   │   └── kustomization.yaml
│   └── app2/
├── infrastructure/          # Infrastructure components
│   ├── argocd/
│   ├── monitoring/
│   └── networking/
└── clusters/               # Cluster-specific configs
    ├── dev/
    ├── staging/
    └── prod/
```

### App of Apps Pattern
```yaml
# apps/argocd-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/gitops
    targetRevision: HEAD
    path: apps
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Sync Policies

### Automated Sync
```yaml
spec:
  syncPolicy:
    automated:
      prune: true      # Delete resources not in Git
      selfHeal: true   # Auto-sync when drift detected
      allowEmpty: false
    syncOptions:
    - Validate=true
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
```

### Sync Waves
Control deployment order:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Deploy first
---
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"  # Deploy second
```

### Hooks
```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

## ApplicationSets

### Git Generator
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
spec:
  generators:
  - git:
      repoURL: https://github.com/myorg/gitops
      revision: HEAD
      directories:
      - path: clusters/*/addons/*
  template:
    metadata:
      name: '{{path.basename}}-{{path[1]}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/gitops
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        name: '{{path[1]}}'
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### List Generator
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  generators:
  - list:
      elements:
      - cluster: dev
        url: https://dev.k8s.local
      - cluster: prod
        url: https://prod.k8s.local
  template:
    metadata:
      name: '{{cluster}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/guestbook
        targetRevision: HEAD
        path: manifests/
      destination:
        server: '{{url}}'
        namespace: guestbook
```

## Multi-Cluster Setup

### Add Cluster
```bash
# Add cluster context
argocd cluster add my-cluster-context

# List clusters
argocd cluster list

# Or manually create secret
kubectl create secret generic cluster-my-cluster \
  -n argocd \
  --from-literal=name=my-cluster \
  --from-literal=server=https://my-cluster.local:6443 \
  --from-literal=config='<kubeconfig-yaml>'
```

### Deploy to Multiple Clusters
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: multi-cluster-app
spec:
  generators:
  - clusters: {}  # All registered clusters
  template:
    metadata:
      name: '{{name}}-app'
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/app
        targetRevision: HEAD
        path: k8s
      destination:
        server: '{{server}}'
        namespace: default
```

## RBAC Configuration

### Project Roles
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-a
spec:
  roles:
  - name: developer
    policies:
    - p, proj:team-a:developer, applications, get, team-a/*, allow
    - p, proj:team-a:developer, applications, sync, team-a/*, allow
    groups:
    - my-org:team-a
  - name: admin
    policies:
    - p, proj:team-a:admin, applications, *, team-a/*, allow
    - p, proj:team-a:admin, repositories, *, *, allow
    groups:
    - my-org:team-a-admins
```

### Global RBAC
```yaml
# argocd-rbac-cm ConfigMap
policy.csv: |
  p, role:readonly, applications, get, */*, allow
  p, role:readonly, certificates, get, *, allow
  p, role:readonly, clusters, get, *, allow
  p, role:readonly, repositories, get, *, allow
  g, my-org:developers, role:readonly
  g, my-org:admins, role:admin
```

## Notifications

### Slack Notifications
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.slack: |
    token: $slack-token
  template.app-deployed: |
    message: |
      {{if eq .serviceType "slack"}}:white_check_mark:{{end}} Application {{.app.metadata.name}} is now running new version.
  trigger.on-deployed: |
    - when: app.status.operationState.phase in ['Succeeded'] and app.status.health.status == 'Healthy'
      send: [app-deployed]
```

### Subscribe to Notifications
```yaml
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-deployed.slack: my-channel
```

## Secrets Management

### Sealed Secrets Integration
```yaml
# Encrypt secret
echo -n mypassword | kubectl create secret generic mysecret \
  --dry-run=client --from-file=password=/dev/stdin -o yaml | \
  kubeseal -o yaml > mysealedsecret.yaml
```

### External Secrets
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
spec:
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: app-secrets
  data:
  - secretKey: password
    remoteRef:
      key: secret/data/app
      property: password
```

### Git-Crypt
```bash
# Initialize git-crypt
git-crypt init

# Add GPG key
git-crypt add-gpg-user user@example.com

# Encrypt files matching .gitattributes
echo "secrets/* filter=git-crypt diff=git-crypt" >> .gitattributes
```

## Monitoring

### Prometheus Metrics
ArgoCD exposes metrics on `:8082/metrics`

Key metrics:
- `argocd_app_health_total`: Application health status
- `argocd_app_sync_total`: Sync operations
- `argocd_git_request_total`: Git operations
- `argocd_kubectl_exec_total`: Kubectl operations

### Grafana Dashboard
Import dashboard: https://grafana.com/grafana/dashboards/14584

## Troubleshooting

### Application Not Syncing
```bash
# Check application status
argocd app get my-app

# View sync details
argocd app sync my-app --dry-run

# Force sync
argocd app sync my-app --force

# Hard refresh (bypass cache)
argocd app sync my-app --hard-refresh
```

### Repository Connection Issues
```bash
# Test repository connection
argocd repo get https://github.com/myorg/myrepo

# Update credentials
argocd repo add https://github.com/myorg/myrepo \
  --username git --password <new-token>
```

### Performance Issues
```bash
# Increase repo server replicas
kubectl scale deployment argocd-repo-server -n argocd --replicas=3

# Clear Redis cache
kubectl exec -n argocd deployment/argocd-redis -- redis-cli FLUSHALL

# Check resource usage
kubectl top pods -n argocd
```

### Debugging Sync Failures
```bash
# Get detailed sync status
argocd app get my-app -o json | jq '.status.conditions'

# View application logs
kubectl logs -n argocd deployment/argocd-application-controller

# Check events
kubectl get events -n <app-namespace> --sort-by='.lastTimestamp'
```

## Best Practices

1. **Repository Structure**
   - Separate app and infrastructure repos
   - Use Kustomize/Helm for templating
   - Environment-specific overlays

2. **Security**
   - Use RBAC and Projects
   - Encrypt secrets in Git
   - Audit access regularly
   - Limit cluster-admin access

3. **Automation**
   - Enable auto-sync for dev/staging
   - Manual sync for production
   - Use sync waves for dependencies
   - Implement proper health checks

4. **Monitoring**
   - Set up alerts for sync failures
   - Monitor Git/Kubernetes API rate limits
   - Track deployment frequency
   - Regular backup of ArgoCD configs