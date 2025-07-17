# Claude Instructions for GMAC.io CI/CD Project

## Project Overview
This is a self-hosted CI/CD infrastructure project using Gitea to replace GitHub Actions/Vercel deployments. The goal is to have full control over the CI/CD system while keeping costs low.

## Current Setup
- **Server**: ci.gmac.io (5.78.92.8) on Hetzner CPX11 ($4.20/month)
- **Platform**: Gitea with Actions (GitHub Actions compatible)
- **Target Apps**: Next.js, Vite, Go, and Rust applications
- **Protocols**: HTTP/HTTPS, WS/WSS, and MQTT

## Key Files
- `docker-compose.yml`: Main Gitea deployment configuration
- `gitea-bulk-import.py`: Interactive script to bulk import GitHub repos
- `setup.sh`: Environment setup script (Python venv, git init)
- `PROJECT_CONTEXT.md`: Detailed project status and progress
- `example-workflows/`: GitHub Actions compatible workflows for different project types

## Server Status
- Gitea is running at https://ci.gmac.io
- User account created with SSH key configured
- Ready for bulk import of GitHub repositories

## Common Commands
When working with this project, you should know these commands:

### Development Setup
```bash
# Set up Python environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Server Management
```bash
# Check Gitea status
ssh root@5.78.92.8 "docker ps"

# View Gitea logs
ssh root@5.78.92.8 "docker logs gitea"

# Restart Gitea
ssh root@5.78.92.8 "cd /opt/gitea && docker-compose restart"
```

### Repository Import
```bash
# Run interactive bulk import
python gitea-bulk-import.py
```

## Next Steps
1. Test the bulk import script to migrate GitHub repositories
2. Set up example workflows for Next.js/Vite/Go/Rust projects
3. Configure automated builds and deployments
4. Implement backup strategy

## Notes
- The server uses Docker Compose for easy management
- All workflows are GitHub Actions compatible
- SSH access is configured for the root user at 5.78.92.8
- DNS is configured via Route 53 for ci.gmac.io domain

When working on this project, always consider cost optimization and maintain the lightweight nature of the setup while ensuring reliability for CI/CD operations.