# Centralized Authentication Component

This component provides centralized GitHub OAuth authentication for all services in the cluster using OAuth2 Proxy.

## Overview

The auth component deploys OAuth2 Proxy at the root domain to handle authentication for all subdomain services. Users authenticate once and can access all protected services without re-authenticating.

## Features

- Single Sign-On (SSO) across all cluster services
- GitHub OAuth integration
- Cookie-based session management
- Support for GitHub organization/user restrictions
- Automatic token refresh
- Header-based authentication passing to backend services

## Prerequisites

1. **GitHub OAuth App**
   - Create at: https://github.com/settings/applications/new
   - Homepage URL: `https://<your-domain>`
   - Authorization callback URL: `https://<your-domain>/oauth2/callback`

2. **Environment Variables**
   ```bash
   export GITHUB_CLIENT_ID="your-client-id"
   export GITHUB_CLIENT_SECRET="your-client-secret"
   export DOMAIN="your-domain.com"
   
   # Optional: Restrict access
   export GITHUB_ORG="your-org"  # Allow only members of this org
   export GITHUB_USER="user1,user2"  # Allow only specific users
   ```

## Installation

```bash
./components/auth/install.sh
```

## How It Works

1. **Root Domain**: OAuth2 proxy handles authentication at `https://<domain>/oauth2/*`
2. **Protected Services**: Services use ingress annotations to require authentication
3. **Session Cookies**: Shared across all subdomains (*.domain.com)
4. **Headers**: User information passed to backend services via headers

## Protecting a Service

Add these annotations to any ingress to require authentication:

```yaml
annotations:
  nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.auth-system.svc.cluster.local:4180/oauth2/auth"
  nginx.ingress.kubernetes.io/auth-signin: "https://${DOMAIN}/oauth2/start?rd=$scheme://$host$escaped_request_uri"
  nginx.ingress.kubernetes.io/auth-response-headers: "X-Auth-Request-User,X-Auth-Request-Email,X-Auth-Request-Access-Token"
```

## Headers Passed to Services

Protected services receive these headers:
- `X-Auth-Request-User`: GitHub username
- `X-Auth-Request-Email`: User's email
- `X-Auth-Request-Access-Token`: GitHub access token
- `Authorization`: Bearer token

## Service URLs

After installation, services will be available at:
- **Grafana**: `https://metrics.<domain>`
- **Prometheus**: `https://prometheus.<domain>`
- **AlertManager**: `https://alerts.<domain>`
- **Gitea**: `https://git.<domain>`
- **Harbor**: `https://registry.<domain>`
- **NPM Registry**: `https://npm.<domain>`
- **K8s Dashboard**: `https://dashboard.<domain>`

## Session Management

- **Cookie Duration**: 24 hours
- **Cookie Refresh**: Every 60 minutes
- **Secure Cookies**: HTTPS only
- **Domain Scope**: *.<your-domain>

## Troubleshooting

### Check OAuth2 Proxy Logs
```bash
kubectl logs -n auth-system deployment/oauth2-proxy
```

### Test Authentication
```bash
curl -I https://<domain>/oauth2/auth
```

### Clear Session
Users can sign out by visiting: `https://<domain>/oauth2/sign_out`

## Security Considerations

- Always use HTTPS in production
- Restrict access using GITHUB_ORG or GITHUB_USER
- Regularly rotate cookie secrets
- Monitor authentication logs