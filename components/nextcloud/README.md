# Nextcloud Component

This component installs Nextcloud, a self-hosted file sync and collaboration platform.

## Features

- **File Sync & Share**: Sync files across devices with desktop and mobile clients
- **Collaborative Editing**: Real-time document collaboration with Office integration
- **Calendar & Contacts**: CalDAV and CardDAV server for personal information management
- **Talk**: Built-in video calls and chat
- **Photos**: Auto-upload and organize photos from mobile devices
- **Notes & Tasks**: Personal productivity tools
- **External Storage**: Connect to S3, FTP, SMB, and more
- **End-to-End Encryption**: Client-side encryption for sensitive files

## Architecture

- Nextcloud server (PHP application)
- PostgreSQL database for metadata
- Redis for caching and file locking
- S3 primary storage (MinIO) when available
- Background job processing via cron

## Access Methods

### Web Interface
- URL: `https://files.<domain>`
- Protected by OAuth2 for browser access
- Full feature access including admin panel

### Sync Clients
- **Desktop**: Windows, macOS, Linux
- **Mobile**: iOS, Android
- Server URL: `https://files.<domain>`
- Use Nextcloud credentials (not OAuth)

### WebDAV Access
- Files: `https://files.<domain>/remote.php/dav/files/username/`
- Calendar: `https://files.<domain>/remote.php/dav/calendars/username/`
- Contacts: `https://files.<domain>/remote.php/dav/addressbooks/users/username/`

## Storage Configuration

### With MinIO (Recommended)
- Primary storage uses S3 (MinIO)
- Unlimited scalable storage
- Better performance for large deployments
- Metadata and previews on local disk

### Without MinIO
- All data stored on local PersistentVolume
- 100Gi allocated by default
- Suitable for smaller deployments

## Initial Setup

1. **Access Admin Panel**
   ```
   URL: https://files.<domain>
   Username: admin
   Password: <from credentials file>
   ```

2. **Configure Email (Settings → Basic settings)**
   ```
   Send mode: SMTP
   Server: your-smtp-server.com:587
   Authentication: Login
   Username: your-email@domain.com
   Password: your-smtp-password
   ```

3. **Install Recommended Apps**
   - Go to Apps → App bundles
   - Install "Groupware" bundle (Calendar, Contacts, Mail)
   - Install "Office" bundle (Collabora, OnlyOffice)

4. **Create Users**
   - Settings → Users
   - Create users or enable registration
   - Set quotas and group memberships

## Client Configuration

### Desktop Client
1. Download from https://nextcloud.com/install/
2. Enter server: `https://files.<domain>`
3. Login with Nextcloud credentials
4. Choose folders to sync

### Mobile Apps
1. Install from App Store/Google Play
2. Server: `https://files.<domain>`
3. Enable auto-upload for photos
4. Configure offline files

### Calendar/Contacts Sync

#### iOS
1. Settings → Accounts → Add Account → Other
2. Add CalDAV/CardDAV Account
3. Server: `files.<domain>`
4. Username and password

#### Android
1. Install DAVx5 from Play Store
2. Add account with base URL: `https://files.<domain>`
3. Login with credentials
4. Select calendars and address books

#### Thunderbird
1. Install TbSync and Provider for CalDAV/CardDAV
2. Add CalDAV: `https://files.<domain>/remote.php/dav/`
3. Autodiscovery will find calendars and contacts

## Apps and Extensions

### Productivity
- **Deck**: Kanban board for project management
- **Tasks**: Task management with CalDAV sync
- **Notes**: Markdown notes with mobile sync
- **Forms**: Create surveys and forms
- **Polls**: Schedule meetings and make decisions

### Collaboration
- **Talk**: Video conferencing and chat
- **Collabora Online**: Edit Office documents
- **OnlyOffice**: Alternative office suite
- **Whiteboard**: Collaborative drawing

### Media
- **Photos**: Photo management with AI tagging
- **Music**: Stream your music collection
- **Video**: Video player with streaming
- **Maps**: View and share locations

### Integration
- **External sites**: Embed external websites
- **External storage**: Mount S3, FTP, SMB
- **LDAP/AD**: Enterprise authentication
- **SSO & SAML**: Single sign-on integration

## Performance Tuning

### PHP Configuration
Already optimized in deployment:
- Memory limit: 512M
- Upload limit: 10G
- OPcache enabled

### Background Jobs
Cron job runs every 5 minutes for:
- File scanning
- Thumbnail generation
- Trash cleanup
- Activity notifications

### Redis Caching
Configured for:
- File locking
- Session handling
- Cache storage

### Large File Uploads
For files over 10GB:
1. Use sync client (chunked upload)
2. Or increase timeout in ingress
3. Or use external storage import

## Security

### Access Control
- OAuth2 for web interface
- App passwords for clients
- Sharing permissions per file/folder
- Password-protected public links

### Encryption
- HTTPS transport encryption
- Server-side encryption available
- End-to-end encryption app
- Encrypted external storage

### Two-Factor Authentication
Enable in user settings:
- TOTP (Google Authenticator)
- WebAuthn/FIDO2
- Backup codes
- SMS (if configured)

### Compliance
- GDPR compliant
- Activity logging
- File access control
- Retention policies

## Backup and Restore

### What to Backup
1. Database (PostgreSQL)
2. Data directory (`/var/www/html/data`)
3. Config file (`/var/www/html/config/config.php`)
4. Apps (`/var/www/html/apps`)

### Backup Commands
```bash
# Database backup
kubectl exec -n nextcloud deployment/nextcloud-postgres -- \
  pg_dump -U nextcloud nextcloud > nextcloud-backup.sql

# Data backup (if not using S3)
kubectl cp nextcloud/$(kubectl get pod -n nextcloud -l app=nextcloud -o jsonpath='{.items[0].metadata.name}'):/var/www/html/data ./nextcloud-data-backup

# Config backup
kubectl cp nextcloud/$(kubectl get pod -n nextcloud -l app=nextcloud -o jsonpath='{.items[0].metadata.name}'):/var/www/html/config/config.php ./config.php.backup
```

### Restore Process
1. Deploy fresh Nextcloud
2. Restore database
3. Restore data directory
4. Restore config.php
5. Run `occ maintenance:repair`

## Troubleshooting

### Maintenance Mode
```bash
# Enable maintenance mode
kubectl exec -n nextcloud deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ maintenance:mode --on"

# Disable maintenance mode
kubectl exec -n nextcloud deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ maintenance:mode --off"
```

### File Scanning
```bash
# Scan all files
kubectl exec -n nextcloud deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ files:scan --all"

# Scan specific user
kubectl exec -n nextcloud deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ files:scan username"
```

### Cache Issues
```bash
# Clear cache
kubectl exec -n nextcloud deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ cache:clear"
```

### Database Issues
```bash
# Add missing indices
kubectl exec -n nextcloud deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ db:add-missing-indices"

# Convert to big int
kubectl exec -n nextcloud deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ db:convert-filecache-bigint"
```

### Common Issues

1. **"Access through untrusted domain"**
   - Check NEXTCLOUD_TRUSTED_DOMAINS env var
   - Or manually add domain via occ config

2. **Slow file uploads**
   - Check PHP memory and timeout settings
   - Use sync client for large files
   - Verify Redis is working

3. **Calendar/Contacts not syncing**
   - Check WebDAV endpoints are accessible
   - Verify ingress allows DAV without OAuth
   - Check client autodiscovery

4. **Background jobs not running**
   - Check cronjob is created
   - Verify cron mode is set
   - Check job status in admin panel

## Integration Examples

### External Storage
```bash
# Add S3 bucket
kubectl exec -n nextcloud deployment/nextcloud -- su -s /bin/bash www-data -c "
  php occ app:enable files_external
  php occ files_external:create \
    'Backup Storage' \
    amazons3 \
    amazons3::accesskey \
    -c bucket=backups \
    -c hostname=s3.<domain> \
    -c port=443 \
    -c use_ssl=true \
    -c use_path_style=true \
    -c key=<access-key> \
    -c secret=<secret-key>
"
```

### LDAP Configuration
```bash
kubectl exec -n nextcloud deployment/nextcloud -- su -s /bin/bash www-data -c "
  php occ app:enable user_ldap
  php occ ldap:create-empty-config
  php occ ldap:set-config s01 ldapHost 'ldap.company.com'
  php occ ldap:set-config s01 ldapPort 389
  php occ ldap:set-config s01 ldapBase 'dc=company,dc=com'
"
```

## Monitoring

### Health Check
- Status endpoint: `/status.php`
- OCS API: `/ocs/v2.php/apps/serverinfo/api/v1/info`

### Prometheus Metrics
Enable serverinfo app for basic metrics:
```bash
kubectl exec -n nextcloud deployment/nextcloud -- \
  su -s /bin/bash www-data -c "php occ app:enable serverinfo"
```

### Logs
```bash
# Nextcloud logs
kubectl logs -n nextcloud deployment/nextcloud

# Access logs
kubectl exec -n nextcloud deployment/nextcloud -- tail -f /var/log/apache2/access.log

# Nextcloud app log
kubectl exec -n nextcloud deployment/nextcloud -- \
  su -s /bin/bash www-data -c "cat /var/www/html/data/nextcloud.log"
```