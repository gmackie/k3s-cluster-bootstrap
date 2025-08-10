# Authentik Component

This component installs Authentik, a self-hosted identity provider with support for OAuth2, SAML, LDAP, and more.

## Features

- **Multi-Protocol Support**: OAuth2/OIDC, SAML, LDAP, Proxy auth
- **User Management**: Self-service portal, admin interface
- **Authentication Flows**: Customizable login/enrollment flows
- **Multi-Factor Auth**: TOTP, WebAuthn, SMS, Email
- **Social Login**: GitHub, Google, Facebook, etc.
- **Application Catalog**: Pre-configured app templates
- **Outposts**: Deploy authentication anywhere
- **API-First**: Full REST API for automation

## Architecture

- **Server**: Main application handling authentication
- **Worker**: Background tasks and outpost management
- **PostgreSQL**: User and configuration storage
- **Redis**: Cache and task queue
- **Outposts**: Proxy/LDAP endpoints (deployed separately)

## Access

- **URL**: `https://auth.<domain>`
- **Admin User**: `akadmin`
- **Admin Password**: See credentials file

## Quick Start

### 1. Initial Login
```
URL: https://auth.<domain>
Username: akadmin
Password: <from credentials file>
```

### 2. Create OAuth2 Provider

1. Navigate to **Providers** → **Create**
2. Select **OAuth2/OpenID Provider**
3. Configure:
   - Name: `My OAuth Provider`
   - Client type: `Confidential`
   - Redirect URIs: `https://app.domain.com/oauth/callback`
   - Scopes: `openid`, `profile`, `email`

### 3. Create Application

1. Navigate to **Applications** → **Create**
2. Configure:
   - Name: `My Application`
   - Slug: `my-app`
   - Provider: Select OAuth provider
   - Launch URL: `https://app.domain.com`

### 4. Get Credentials

1. View the provider details
2. Copy Client ID and Client Secret
3. Configure your application

## Provider Types

### OAuth2/OpenID Connect
Perfect for modern applications:
```yaml
# Example application configuration
OAUTH_CLIENT_ID: "your-client-id"
OAUTH_CLIENT_SECRET: "your-client-secret"
OAUTH_ISSUER: "https://auth.domain.com/application/o/my-app/"
OAUTH_AUTH_URL: "https://auth.domain.com/application/o/authorize/"
OAUTH_TOKEN_URL: "https://auth.domain.com/application/o/token/"
OAUTH_USERINFO_URL: "https://auth.domain.com/application/o/userinfo/"
```

### SAML
For enterprise applications:
1. Create SAML Provider
2. Configure:
   - ACS URL: `https://app.domain.com/saml/acs`
   - Audience: `https://app.domain.com`
   - Signing certificate: Auto-generated
3. Download metadata XML

### LDAP
Via LDAP Outpost:
1. Create LDAP Provider
2. Configure:
   - Base DN: `dc=company,dc=com`
   - Bind flow: Create or select
3. Deploy LDAP outpost
4. Connect: `ldap://ldap.domain.com`

### Proxy
For legacy applications:
1. Create Proxy Provider
2. Configure:
   - External host: `https://legacy.domain.com`
   - Internal host: `http://legacy-app:8080`
3. Deploy Proxy outpost

## Authentication Flows

### Default Flows
- **Authentication**: Login flow
- **Authorization**: Consent flow
- **Enrollment**: Registration flow
- **Recovery**: Password reset flow
- **Unenrollment**: Account deletion

### Custom Flow Example
Create a flow requiring MFA:
1. Create new flow
2. Add stages:
   - Identification stage
   - Password stage
   - MFA stage (TOTP/WebAuthn)
   - User login stage

## User Sources

### LDAP Integration
```yaml
# Sync users from Active Directory
Server URI: ldap://ad.company.com
Bind DN: CN=authentik,CN=Users,DC=company,DC=com
Base DN: DC=company,DC=com
```

### OAuth Sources
Add social login:
1. **Sources** → **Create** → **OAuth Source**
2. Select provider (GitHub, Google, etc.)
3. Enter OAuth credentials
4. Configure user matching

## Multi-Factor Authentication

### TOTP (Authenticator Apps)
1. **Flows & Stages** → **Stages**
2. Create **TOTP Authenticator Setup Stage**
3. Add to authentication flow

### WebAuthn (Security Keys)
1. Create **WebAuthn Authenticator Setup Stage**
2. Configure:
   - User verification: Required
   - Resident key requirement: Preferred

### Email/SMS
1. Configure email/SMS provider
2. Create **Email/SMS Stage**
3. Add to flow with validation stage

## Application Integration

### Kubernetes/OAuth2 Proxy
Replace GitHub OAuth with Authentik:
```yaml
# oauth2-proxy configuration
- --provider=oidc
- --oidc-issuer-url=https://auth.domain.com/application/o/oauth2-proxy/
- --client-id=<client-id>
- --client-secret=<client-secret>
- --email-domain=*
- --scope=openid profile email
- --redirect-url=https://domain.com/oauth2/callback
```

### Grafana
```ini
[auth.generic_oauth]
enabled = true
name = Authentik
client_id = <client-id>
client_secret = <client-secret>
scopes = openid profile email
auth_url = https://auth.domain.com/application/o/authorize/
token_url = https://auth.domain.com/application/o/token/
api_url = https://auth.domain.com/application/o/userinfo/
```

### GitLab
```yaml
gitlab_rails['omniauth_providers'] = [
  {
    "name" => "openid_connect",
    "label" => "Authentik",
    "args" => {
      "name" => "openid_connect",
      "scope" => ["openid", "profile", "email"],
      "response_type" => "code",
      "issuer" => "https://auth.domain.com/application/o/gitlab/",
      "client_auth_method" => "query",
      "discovery" => true,
      "uid_field" => "preferred_username",
      "client_options" => {
        "identifier" => "<client-id>",
        "secret" => "<client-secret>",
      }
    }
  }
]
```

## Outposts

### Proxy Outpost
Deploy authentication proxy:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: authentik-proxy
spec:
  template:
    spec:
      containers:
      - name: proxy
        image: ghcr.io/goauthentik/proxy:2023.10.5
        env:
        - name: AUTHENTIK_HOST
          value: https://auth.domain.com
        - name: AUTHENTIK_TOKEN
          valueFrom:
            secretKeyRef:
              name: authentik-outpost
              key: token
```

### LDAP Outpost
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: authentik-ldap
spec:
  template:
    spec:
      containers:
      - name: ldap
        image: ghcr.io/goauthentik/ldap:2023.10.5
        ports:
        - containerPort: 389
          name: ldap
        - containerPort: 636
          name: ldaps
```

## API Usage

### Authentication
```bash
# Get API token from UI or use bootstrap token
TOKEN="your-api-token"

# List users
curl -H "Authorization: Bearer $TOKEN" \
  https://auth.domain.com/api/v3/core/users/

# Create user
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username": "newuser", "email": "user@example.com", "is_active": true}' \
  https://auth.domain.com/api/v3/core/users/
```

### Application Management
```python
import requests

headers = {"Authorization": f"Bearer {token}"}
base_url = "https://auth.domain.com/api/v3"

# List applications
apps = requests.get(f"{base_url}/core/applications/", headers=headers).json()

# Create provider
provider = requests.post(f"{base_url}/providers/oauth2/", headers=headers, json={
    "name": "My App OAuth",
    "authorization_flow": "default-authorization-flow",
    "client_type": "confidential",
    "redirect_uris": "https://myapp.com/oauth/callback"
}).json()
```

## Security Best Practices

1. **Strong Passwords**
   - Configure password policy
   - Enforce complexity requirements
   - Set expiration if needed

2. **MFA Enforcement**
   - Require MFA for admin users
   - Enable for sensitive applications
   - Support multiple MFA methods

3. **Session Management**
   - Configure session timeout
   - Enable concurrent session limits
   - Force re-authentication for sensitive operations

4. **Audit Logging**
   - Enable event logging
   - Monitor failed authentications
   - Set up alerts for suspicious activity

## Troubleshooting

### Login Issues
1. Check flow configuration
2. Verify provider settings
3. Review event logs in UI
4. Check worker logs:
   ```bash
   kubectl logs -n authentik deployment/authentik-worker
   ```

### OAuth Errors
1. Verify redirect URIs match exactly
2. Check client ID/secret
3. Ensure scopes are configured
4. Review provider logs

### LDAP Connection
1. Test with ldapsearch:
   ```bash
   ldapsearch -H ldap://ldap.domain.com -D "cn=user,dc=domain,dc=com" -w password -b "dc=domain,dc=com"
   ```
2. Check outpost deployment
3. Verify bind credentials

### Performance
1. Scale workers:
   ```bash
   kubectl scale deployment/authentik-worker -n authentik --replicas=4
   ```
2. Monitor Redis memory
3. Check PostgreSQL performance
4. Review slow flows

## Backup

Critical data:
1. PostgreSQL database
2. Media files (`/media`)
3. Certificates and keys

```bash
# Database backup
kubectl exec -n authentik deployment/authentik-postgres -- \
  pg_dump -U authentik authentik > authentik-backup.sql

# Media backup
kubectl cp authentik/$(kubectl get pod -n authentik -l app=authentik-server -o jsonpath='{.items[0].metadata.name}'):/media ./authentik-media-backup
```

## Migration from OAuth2 Proxy

To migrate from simple OAuth2 proxy to Authentik:

1. **Create OAuth2 Provider** in Authentik matching GitHub OAuth
2. **Update ingress annotations**:
   ```yaml
   # Old
   nginx.ingress.kubernetes.io/auth-url: "http://oauth2-proxy.auth-system.svc.cluster.local:4180/oauth2/auth"
   
   # New
   nginx.ingress.kubernetes.io/auth-url: "http://authentik-proxy.authentik.svc.cluster.local:9000/outpost.goauthentik.io/auth/nginx"
   ```
3. **Deploy proxy outpost**
4. **Test authentication flow**
5. **Migrate users if needed**