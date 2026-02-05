# Canvas LMS Component

Instructure Canvas LMS for LTI integration testing.

## Features
- Canvas LMS with PostgreSQL backend
- Redis for caching and jobs
- LTI 1.3 + Advantage support (Developer Keys)
- Authentik SSO integration ready

## Prerequisites
- Base cluster components installed
- Longhorn storage available
- Domain configured

## Installation
```bash
export KUBECONFIG=~/.kube/config-hetzner
export DOMAIN=gmac.io
./components/canvas/install.sh
```

## Access
- URL: https://canvas.gmac.io
- Admin credentials: See `.cluster/credentials/canvas.conf`

## LTI 1.3 Configuration
1. Login as admin
2. Admin → Developer Keys → + Developer Key → + LTI Key
3. Configure your LTI tool settings
4. Enable the key (toggle to ON)

## Notes
- Canvas is resource-intensive; initial page loads may be slow
- Background jobs process asynchronously via canvas-jobs
- Uses Instructure's community Docker images
