# GMAC.io CI/CD Infrastructure

Self-hosted CI/CD solution using Gitea with GitHub Actions compatibility.

## Features

- Complete Git hosting solution
- GitHub Actions compatible CI/CD
- Bulk import from GitHub
- Support for Next.js, Vite, Go, and Rust projects
- SST integration for serverless deployments
- Cost-effective (~$6/month on Hetzner CPX11)

## Quick Start

### 1. Setup Development Environment

```bash
# Create virtual environment and install dependencies
./setup.sh

# Activate virtual environment
source venv/bin/activate
```

### 2. Deploy Gitea

Server is already deployed at: https://ci.gmac.io

To deploy a new instance:
```bash
# Using Docker Compose (recommended)
ssh root@your-server
cd /opt/gitea
docker-compose up -d

# Or use the setup script
bash setup-gitea-ci.sh
```

### 3. Import GitHub Repositories

```bash
# Activate virtual environment
source venv/bin/activate

# Run interactive import script
python gitea-bulk-import.py
```

The script will:
- Prompt for Gitea API token
- Prompt for GitHub credentials
- Let you select which repos to import
- Import with issues, PRs, and releases

## Project Structure

```
.
├── gitea-bulk-import.py      # Interactive GitHub import script
├── docker-compose.yml         # Gitea deployment config
├── example-workflows/         # CI/CD workflow examples
│   ├── nextjs-sst.yml
│   ├── go-service.yml
│   └── rust-service.yml
├── setup-scripts/            # Server setup automation
│   ├── setup-gitea-ci.sh
│   ├── deploy-cpx11.sh
│   └── deploy-hetzner.sh
└── docs/
    ├── ci-architecture.md
    └── github-migration.md
```

## Configuration

### Gitea API Access
1. Visit https://ci.gmac.io/user/settings/applications
2. Generate new token with `repo` scope

### GitHub Token (for private repos)
1. Visit https://github.com/settings/tokens
2. Create token with `repo` scope

## Server Details

- **Host**: Hetzner CPX11 (2 vCPU, 2GB RAM, 40GB SSD)
- **IP**: 5.78.92.8
- **Domain**: ci.gmac.io
- **Services**:
  - Gitea (Git hosting + Web UI)
  - Gitea Actions (CI/CD runner)
  - Nginx (reverse proxy + SSL)

## Maintenance

### Check disk usage
```bash
ssh root@ci.gmac.io
df -h
docker system df
```

### Update Gitea
```bash
ssh root@ci.gmac.io
cd /opt/gitea
docker-compose pull
docker-compose up -d
```

### Backup
```bash
# Backup Gitea data
docker exec -u git gitea sh -c 'gitea dump -c /data/gitea/conf/app.ini'
```

## Support

- Gitea docs: https://docs.gitea.io
- GitHub migration: See `github-migration.md`
- Architecture: See `ci-architecture.md`