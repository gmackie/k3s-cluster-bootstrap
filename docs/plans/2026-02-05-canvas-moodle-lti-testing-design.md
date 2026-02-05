# Canvas & Moodle LTI Testing Environment Design

**Date:** 2026-02-05
**Purpose:** Production-level LTI 1.3 integration testing for education software

## Overview

Deploy Canvas LMS and Moodle LMS on the gmac.io Kubernetes cluster for LTI 1.3 + Advantage integration testing. Both platforms will use Authentik SSO for admin authentication.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    gmac.io Cluster                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  Authentik  │    │   Canvas    │    │   Moodle    │     │
│  │ auth.gmac.io│◄───│canvas.gmac.io│   │moodle.gmac.io│    │
│  └─────────────┘    └──────┬──────┘    └──────┬──────┘     │
│         │                  │                  │             │
│         │           ┌──────┴──────┐    ┌──────┴──────┐     │
│         │           │  PostgreSQL │    │  PostgreSQL │     │
│         │           │   (Canvas)  │    │  (Moodle)   │     │
│         │           └─────────────┘    └─────────────┘     │
│         │                                                   │
│         └──────────── OIDC SSO ────────────────────────────│
│                                                             │
│  Ingress: NGINX + cert-manager (Let's Encrypt)             │
│  Storage: Longhorn (persistent volumes)                     │
└─────────────────────────────────────────────────────────────┘
```

## Components

### Canvas LMS

- **Namespace:** `canvas`
- **URL:** `https://canvas.gmac.io`
- **Image:** `instructure/canvas-lms` (official Instructure images)
- **LTI Support:** LTI 1.3 + Advantage (Deep Linking, AGS, NRPS)

**Components:**
| Component | Purpose | Resources |
|-----------|---------|-----------|
| canvas-web | Rails application | 512Mi-1Gi RAM, 500m CPU |
| canvas-jobs | Background job processor | 256Mi-512Mi RAM, 250m CPU |
| canvas-postgres | PostgreSQL 12 database | 256Mi RAM, 5Gi storage |
| canvas-redis | Session/cache store | 128Mi RAM |

### Moodle LMS

- **Namespace:** `moodle`
- **URL:** `https://moodle.gmac.io`
- **Deployment:** Bitnami Helm chart
- **LTI Support:** LTI 1.3 + Advantage via External Tool plugin

**Components:**
| Component | Purpose | Resources |
|-----------|---------|-----------|
| moodle | PHP application | 512Mi-1Gi RAM, 500m CPU |
| moodle-postgres | PostgreSQL 15 database | 256Mi RAM, 5Gi storage |

### Authentik Integration

Both LMS platforms will use Authentik as an OIDC identity provider.

**Authentik Configuration:**
- Two OIDC providers: `canvas-oidc` and `moodle-oidc`
- Two applications: "Canvas LMS" and "Moodle LMS"
- Standard OIDC endpoints at `auth.gmac.io`

**OIDC Endpoints:**
- Authorization: `https://auth.gmac.io/application/o/authorize/`
- Token: `https://auth.gmac.io/application/o/token/`
- UserInfo: `https://auth.gmac.io/application/o/userinfo/`
- JWKS: `https://auth.gmac.io/application/o/jwks/`

## File Structure

```
components/
├── canvas/
│   ├── install.sh              # Main installer script
│   ├── canvas-deployment.yaml  # Web + Jobs deployments
│   ├── canvas-postgres.yaml    # PostgreSQL StatefulSet
│   ├── canvas-redis.yaml       # Redis deployment
│   ├── canvas-ingress.yaml     # Ingress with TLS
│   └── README.md
└── moodle/
    ├── install.sh              # Main installer script
    ├── values.yaml             # Bitnami Helm values
    └── README.md
```

## Installation Process

### Prerequisites
1. Authentik running at `auth.gmac.io`
2. `~/.kube/config-hetzner` configured
3. Longhorn storage available

### Installation Order
1. Install Moodle (faster, validates cluster setup)
2. Install Canvas (slower, more complex)
3. Configure Authentik OIDC providers
4. Configure LTI 1.3 tools in each LMS

### Commands
```bash
export KUBECONFIG=~/.kube/config-hetzner
./components/moodle/install.sh
./components/canvas/install.sh
```

### Credentials
Stored in `.cluster/credentials/`:
- `canvas.conf` - Admin user, DB password, Authentik client ID/secret
- `moodle.conf` - Admin user, DB password, Authentik client ID/secret

## Post-Installation Configuration

### Authentik Setup (Manual)
1. Log into `auth.gmac.io` as admin
2. Create Application "Canvas LMS" with OIDC provider
3. Create Application "Moodle LMS" with OIDC provider
4. Note client IDs and secrets

### Canvas LTI 1.3 Setup (Manual)
1. Log into Canvas as admin
2. Navigate to Admin → Developer Keys
3. Create LTI Key with your tool's configuration
4. Enable the key and note the client ID

### Moodle LTI 1.3 Setup (Manual)
1. Log into Moodle as admin
2. Navigate to Site Administration → Plugins → Activity modules → External tool
3. Add external tool with LTI 1.3 configuration
4. Configure platform ID, client ID, deployment ID

## LTI 1.3 + Advantage Features

Both platforms support:
- **Deep Linking** - Content item selection and embedding
- **Assignment and Grade Services (AGS)** - Grade passback
- **Names and Role Provisioning Services (NRPS)** - Course roster access

## Future Considerations

- **Ephemeral instances:** For CI/CD automated testing (deferred)
- **Resource scaling:** Can increase resources if performance is insufficient
- **Additional LMS platforms:** Could add Blackboard, Brightspace, etc.

## Trade-offs

| Decision | Trade-off |
|----------|-----------|
| Minimal resources | Slower performance, but sufficient for LTI testing |
| Dedicated databases | More resource usage, but clean isolation per LMS |
| Instructure images for Canvas | Complex setup, but most production-realistic |
| Bitnami Helm for Moodle | Less customizable, but faster deployment |
