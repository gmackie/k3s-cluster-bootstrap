# Self-Hosted CI/CD Architecture

## Overview
Cost-effective, self-hosted CI/CD solution for Next.js, Vite, Go, and Rust applications with SST integration.

## Infrastructure Components

### 1. CI/CD Server (Gitea + Gitea Actions)
- **Host**: Single VPS (2-4GB RAM, 2 vCPU)
- **Services**:
  - Gitea (Git hosting + web UI)
  - Gitea Actions Runner
  - Docker Registry (optional)
  - Nginx (reverse proxy)

### 2. Build Agents
- **Option A**: Same VPS as CI server (for low cost)
- **Option B**: Separate build agents (for scale)
- **Docker-in-Docker** for isolated builds

### 3. Deployment Targets
- **Frontend (Next.js/Vite)**: 
  - SST for serverless
  - S3 + CloudFront for static
  - Self-hosted with PM2/Docker
- **Backend (Go/Rust)**:
  - SST for serverless functions
  - ECS/Fargate for containers
  - Self-hosted VPS with systemd

## Pipeline Architecture

```yaml
# Example .gitea/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  build-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
      - run: npm ci
      - run: npm run build
      - run: npx sst deploy --stage prod

  build-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-go@v4  # or rust
      - run: go build -o app
      - run: docker build -t app:${{ github.sha }} .
      - run: npx sst deploy --stage prod
```

## Cost Breakdown
- **VPS for CI/CD**: $10-20/month (Hetzner/DigitalOcean)
- **SST/AWS**: Pay-per-use (typically $5-50/month)
- **Total**: ~$15-70/month vs $100s with GitHub Actions

## Security Considerations
- VPN or Tailscale for secure access
- GitHub webhooks over HTTPS
- Secrets management via Gitea
- Build isolation with Docker

## Migration Path
1. Set up Gitea + Actions on VPS
2. Mirror GitHub repos to Gitea
3. Convert GitHub Actions to Gitea Actions
4. Test with staging environments
5. Switch webhooks from GitHub to Gitea
6. Gradually migrate production deployments