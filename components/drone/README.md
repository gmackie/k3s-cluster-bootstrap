# Drone CI Component

This component installs Drone CI integrated with Gitea for container-native CI/CD pipelines.

## Features

- Container-native CI/CD platform
- Deep integration with Gitea
- Multiple runner types (Docker and Kubernetes)
- PostgreSQL backend for reliability
- OAuth2 authentication via Gitea
- Webhook-based automatic builds

## Prerequisites

1. **Gitea must be installed** - Drone integrates with Gitea for authentication and repositories
2. **Domain configured** - Required for proper OAuth redirect URLs

## Post-Installation Setup

After installing Drone, you must manually configure OAuth in Gitea:

1. Login to Gitea as admin: `https://git.<domain>`
2. Go to Settings → Applications
3. Create new OAuth2 Application:
   - **Application Name**: Drone CI
   - **Redirect URI**: `https://ci.<domain>/login`
4. Copy the Client ID and Client Secret
5. Update Drone deployment with the real OAuth credentials:
   ```bash
   kubectl edit deployment drone-server -n drone
   # Update DRONE_GITEA_CLIENT_ID and DRONE_GITEA_CLIENT_SECRET
   ```

## Writing Drone Pipelines

Create a `.drone.yml` file in your repository root:

### Example Node.js Pipeline
```yaml
---
kind: pipeline
type: kubernetes
name: default

steps:
- name: test
  image: node:18
  commands:
  - npm install
  - npm test

- name: build
  image: node:18
  commands:
  - npm run build

- name: docker
  image: plugins/docker
  settings:
    repo: registry.domain.com/myapp
    tags: 
    - latest
    - ${DRONE_TAG}
    registry: registry.domain.com
    username:
      from_secret: docker_username
    password:
      from_secret: docker_password
  when:
    event:
    - tag
    - push
    branch:
    - main
```

### Example Go Pipeline
```yaml
---
kind: pipeline
type: docker
name: default

steps:
- name: test
  image: golang:1.21
  commands:
  - go test ./...

- name: build
  image: golang:1.21
  commands:
  - go build -o app

- name: docker
  image: plugins/docker
  settings:
    repo: registry.domain.com/myapp
    tags: latest
```

## Runner Types

### Docker Runner
- Runs pipelines in Docker containers
- Good for most use cases
- Requires Docker socket access
- 2 replicas by default

### Kubernetes Runner
- Runs pipelines as Kubernetes pods
- Better isolation and resource management
- Good for larger workloads
- No Docker daemon required

## Secrets Management

Add secrets in Drone UI for sensitive data:

1. Go to repository settings in Drone
2. Add secrets like:
   - `docker_username`
   - `docker_password`
   - `npm_token`
   - etc.

## Comparison with Gitea Actions

| Feature | Drone CI | Gitea Actions |
|---------|----------|---------------|
| Syntax | Simple YAML | GitHub Actions compatible |
| Runners | Docker/K8s native | Container-based |
| UI | Dedicated UI | Integrated in Gitea |
| Plugins | Rich ecosystem | Growing ecosystem |
| Resource usage | Lightweight | Moderate |
| Multi-pipeline | Yes | Yes |
| Secrets | Built-in UI | Via Gitea |

## Troubleshooting

### Check Drone server logs
```bash
kubectl logs -n drone deployment/drone-server
```

### Check runner logs
```bash
kubectl logs -n drone deployment/drone-runner-docker
kubectl logs -n drone deployment/drone-runner-kube
```

### Webhook issues
Ensure Gitea can reach Drone:
```bash
kubectl exec -n gitea deployment/gitea -- curl -I https://ci.domain.com
```

### Build not triggering
1. Check webhook in Gitea repository settings
2. Verify OAuth application is configured correctly
3. Check Drone server logs for webhook errors

## Resource Requirements

- **Drone Server**: 256Mi memory, 100m CPU
- **Docker Runner**: 256Mi-2Gi memory, 100m-2000m CPU
- **Kubernetes Runner**: 64Mi memory, 50m CPU
- **PostgreSQL**: 256Mi memory, 100m CPU