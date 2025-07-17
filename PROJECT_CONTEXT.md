# GMAC.io CI/CD Project Context

## Current Status
- **Date**: July 16, 2025
- **Objective**: Set up self-hosted CI/CD with Gitea replacing GitHub Actions/Vercel
- **Server**: Deployed at ci.gmac.io (5.78.92.8) on Hetzner CPX11

## Completed Tasks
1. ✅ Researched and recommended Gitea as CI/CD solution
2. ✅ Deployed Gitea on Hetzner CPX11 ($4.20/month)
3. ✅ Configured DNS (ci.gmac.io → 5.78.92.8)
4. ✅ Set up Docker Compose configuration
5. ✅ Created bulk import script for GitHub repos
6. ✅ Made import script interactive with token prompts
7. ✅ Created example workflows for Next.js, Go, Rust
8. ✅ Set up Python venv and .gitignore

## Server Configuration
- **Host**: Hetzner CPX11 (2 vCPU, 2GB RAM, 40GB SSD)
- **OS**: Ubuntu 22.04
- **Services Running**:
  - Gitea (port 3000)
  - Gitea runner
  - Nginx (reverse proxy)
  - Docker & Docker Compose

## Next Steps
1. Run `setup.sh` to initialize git repo and venv
2. Test the bulk import script with your GitHub repos
3. Configure Gitea runners for CI/CD
4. Migrate workflows from GitHub Actions
5. Set up SST integration for deployments

## Key Files Created
- `gitea-bulk-import.py` - Interactive GitHub import tool
- `docker-compose.yml` - Gitea deployment config
- `example-workflows/` - CI/CD templates
- `setup.sh` - Project setup script
- `requirements.txt` - Python dependencies
- `.gitignore` - Git ignore rules

## Commands to Resume
```bash
cd /Volumes/dev/gmac-io-ci
chmod +x setup.sh
./setup.sh
source venv/bin/activate
python gitea-bulk-import.py
```

## Repository Goals
- Host many Next.js and Vite web apps
- Host Go and Rust backend services
- Support HTTP/HTTPS, WS/WSS, and MQTT
- Integrate with SST for serverless deployments
- Low cost and full control

## Technical Decisions
- Gitea over Jenkins (lighter, GitHub Actions compatible)
- CPX11 over CPX21 (cost optimization, can upgrade later)
- SQLite over PostgreSQL (lower memory usage)
- Docker Compose deployment (easier management)