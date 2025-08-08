# Vaultwarden Component

This component installs Vaultwarden (formerly Bitwarden_RS), a lightweight self-hosted password manager compatible with Bitwarden clients.

## Features

- **Bitwarden Compatible**: Works with all official Bitwarden apps and browser extensions
- **PostgreSQL Backend**: Reliable database storage for passwords
- **WebSocket Support**: Real-time sync across devices
- **Admin Panel**: Web-based administration interface
- **Organization Support**: Share passwords within teams
- **Send Feature**: Securely share text and files
- **Emergency Access**: Grant trusted contacts emergency access
- **OAuth Integration**: Protected by cluster-wide GitHub OAuth

## Architecture

- Vaultwarden server (Rust implementation)
- PostgreSQL database for data storage
- Persistent volume for attachments and icons
- WebSocket server for real-time sync

## Security Configuration

### Authentication
- **Web UI**: Protected by OAuth2 proxy (GitHub authentication)
- **API/Apps**: Open for mobile and desktop app access
- **Admin Panel**: Requires admin token

### User Management
- Sign-ups disabled by default
- Invitation-only registration
- Admin must invite users via admin panel

## Usage

### Admin Access
1. Access admin panel: `https://vault.<domain>/admin`
2. Enter admin token from credentials file
3. Configure SMTP settings
4. Invite users

### User Access
1. Receive invitation email
2. Register account at `https://vault.<domain>`
3. Install Bitwarden apps/extensions
4. Configure server URL: `https://vault.<domain>`

### Client Configuration

#### Mobile Apps (iOS/Android)
1. Download official Bitwarden app
2. On login screen, tap settings icon
3. Enter server URL: `https://vault.<domain>`
4. Login with your credentials

#### Browser Extensions
1. Install Bitwarden extension
2. Click settings icon on login screen
3. Enter server URL: `https://vault.<domain>`
4. Login with your credentials

#### Desktop Apps
1. Download Bitwarden desktop app
2. Before logging in, click settings
3. Enter server URL: `https://vault.<domain>`
4. Login with your credentials

## Backup Considerations

Critical data to backup:
- PostgreSQL database (automated via pg_dump)
- `/data` directory (attachments, icons)
- Admin token and credentials

Backup command example:
```bash
# Database backup
kubectl exec -n vaultwarden deployment/vaultwarden-postgres -- \
  pg_dump -U vaultwarden vaultwarden > vaultwarden-backup.sql

# Data directory backup
kubectl cp vaultwarden/$(kubectl get pod -n vaultwarden -l app=vaultwarden -o jsonpath='{.items[0].metadata.name}'):/data ./vaultwarden-data-backup
```

## Environment Variables

Key configuration options:
- `SIGNUPS_ALLOWED`: Set to "true" to allow public registration
- `INVITATIONS_ALLOWED`: Allow users to be invited
- `SHOW_PASSWORD_HINT`: Display password hints on login
- `DOMAIN`: Full URL including protocol
- `SMTP_*`: Email configuration for invitations

## Troubleshooting

### Cannot sync with mobile app
1. Ensure WebSocket endpoint is accessible
2. Check ingress allows `/notifications/hub` without auth
3. Verify server URL includes https://

### Admin panel access denied
1. Check admin token in credentials file
2. Ensure you're accessing `/admin` path
3. Token must be entered exactly (no spaces)

### Invitation emails not sending
1. Configure SMTP settings in admin panel
2. Check SMTP credentials and server
3. Verify firewall allows SMTP port

### Database connection issues
```bash
kubectl logs -n vaultwarden deployment/vaultwarden
kubectl logs -n vaultwarden deployment/vaultwarden-postgres
```

## Resource Requirements

- **Vaultwarden**: 128Mi-256Mi memory, 50m-500m CPU
- **PostgreSQL**: 256Mi-512Mi memory, 100m-500m CPU
- **Storage**: 5Gi for database, 5Gi for data

## Security Best Practices

1. **Strong Master Passwords**: Enforce minimum complexity
2. **Two-Factor Authentication**: Enable for all accounts
3. **Regular Backups**: Automate database and data backups
4. **Admin Token**: Store securely, rotate periodically
5. **HTTPS Only**: Never access over plain HTTP
6. **Network Policies**: Restrict database access

## Integration with Cluster

- Uses cluster-wide OAuth2 proxy for web UI
- Integrates with cert-manager for TLS
- Compatible with cluster backup solution
- Monitored by Prometheus/Grafana stack