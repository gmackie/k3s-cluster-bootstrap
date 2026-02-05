# Moodle LMS Component

Moodle learning management system for LTI integration testing.

## Features
- Moodle LMS with PostgreSQL backend
- LTI 1.3 + Advantage support
- Authentik SSO integration ready
- Minimal resource footprint

## Prerequisites
- Base cluster components installed
- Longhorn storage available
- Domain configured

## Installation
```bash
export KUBECONFIG=~/.kube/config-hetzner
export DOMAIN=gmac.io
./components/moodle/install.sh
```

## Access
- URL: https://moodle.gmac.io
- Admin credentials: See `.cluster/credentials/moodle.conf`

## LTI 1.3 Configuration
1. Login as admin
2. Site Administration → Plugins → Activity modules → External tool
3. Manage tools → Configure a tool manually
4. Enter your LTI tool details (client ID, deployment ID, etc.)
