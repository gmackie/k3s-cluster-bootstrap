# Sentry Component

This component installs Sentry, an open-source application monitoring platform that helps developers identify and fix crashes in real time.

## Features

- **Error Tracking**: Capture and track errors across all your applications
- **Performance Monitoring**: Monitor application performance and identify bottlenecks
- **Release Tracking**: Associate errors with specific releases
- **User Feedback**: Collect user feedback when errors occur
- **Issue Management**: Assign, resolve, and track issue status
- **Alerting**: Real-time notifications for critical issues
- **Integrations**: Connect with GitHub, Slack, Jira, and more
- **Source Maps**: Debug minified JavaScript with source map support

## Architecture

- Sentry web service (2 replicas)
- Sentry workers for background processing (2 replicas)
- Sentry cron for scheduled tasks
- PostgreSQL for metadata storage
- Redis for caching and queues
- File storage for event data

## Access

- **URL**: `https://sentry.<domain>`
- **Authentication**: Protected by OAuth2 proxy
- **API Access**: `/api/*` endpoints bypass OAuth for SDK access

## Initial Setup

1. **Login as Admin**
   ```
   Email: admin@<domain>
   Password: <from credentials file>
   ```

2. **Create Organization**
   - Choose organization name
   - Set organization slug (URL-friendly name)

3. **Create First Project**
   - Select platform (JavaScript, Python, Go, etc.)
   - Choose project name
   - Get DSN (Data Source Name)

4. **Configure Applications**
   - Install Sentry SDK for your platform
   - Configure with project DSN
   - Deploy and test error capture

## SDK Integration Examples

### JavaScript/TypeScript (Browser)
```javascript
import * as Sentry from "@sentry/browser";

Sentry.init({
  dsn: "https://<key>@sentry.<domain>/<project>",
  environment: "production",
  integrations: [
    new Sentry.BrowserTracing(),
  ],
  tracesSampleRate: 1.0,
});
```

### Node.js/Express
```javascript
const Sentry = require("@sentry/node");
const Tracing = require("@sentry/tracing");

Sentry.init({
  dsn: "https://<key>@sentry.<domain>/<project>",
  environment: process.env.NODE_ENV,
  integrations: [
    new Sentry.Integrations.Http({ tracing: true }),
    new Tracing.Integrations.Express({ app }),
  ],
  tracesSampleRate: 1.0,
});

app.use(Sentry.Handlers.requestHandler());
app.use(Sentry.Handlers.tracingHandler());
```

### Python/Django
```python
import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

sentry_sdk.init(
    dsn="https://<key>@sentry.<domain>/<project>",
    integrations=[DjangoIntegration()],
    traces_sample_rate=1.0,
    send_default_pii=True,
    environment="production",
)
```

### Go
```go
import (
    "github.com/getsentry/sentry-go"
)

err := sentry.Init(sentry.ClientOptions{
    Dsn: "https://<key>@sentry.<domain>/<project>",
    Environment: "production",
    TracesSampleRate: 1.0,
})

defer sentry.Flush(2 * time.Second)

// Capture errors
if err != nil {
    sentry.CaptureException(err)
}
```

### Docker/Kubernetes
```yaml
# Add to deployment environment variables
env:
- name: SENTRY_DSN
  value: "https://<key>@sentry.<domain>/<project>"
- name: SENTRY_ENVIRONMENT
  value: "production"
- name: SENTRY_RELEASE
  value: "myapp@1.0.0"
```

## Performance Monitoring

Enable performance monitoring to track:
- Transaction duration
- Database queries
- HTTP requests
- Cache performance
- Custom spans

```javascript
// Custom transaction
const transaction = Sentry.startTransaction({
  op: "task",
  name: "My Task",
});

Sentry.getCurrentHub().configureScope(scope => {
  scope.setSpan(transaction);
});

// ... do work ...

transaction.finish();
```

## Issue Management

### Issue States
- **Unresolved**: New or reopened issues
- **Resolved**: Fixed issues
- **Ignored**: Known issues to ignore
- **Resolved in Next Release**: Pending deployment

### Workflow
1. Error occurs → Issue created
2. Developer assigns issue
3. Fix deployed with release tag
4. Issue auto-resolved if no recurrence

## Alerting Rules

Create alerts for:
- Error rate thresholds
- New issues
- Regression detection
- Performance degradation
- Quota usage

Example alert rule:
```
When: Error count > 100 in 5 minutes
Then: Send to #alerts Slack channel
```

## Integrations

### GitHub Integration
1. Settings → Integrations → GitHub
2. Configure repository access
3. Link issues to GitHub issues
4. Track commits and releases

### Slack Integration
1. Settings → Integrations → Slack
2. Add to workspace
3. Configure alert rules
4. Get notifications in channels

### Source Maps (JavaScript)
Upload source maps for production builds:
```bash
# Using sentry-cli
sentry-cli releases files <release> upload-sourcemaps ./dist

# Using webpack plugin
const SentryWebpackPlugin = require("@sentry/webpack-plugin");

plugins: [
  new SentryWebpackPlugin({
    authToken: process.env.SENTRY_AUTH_TOKEN,
    org: "my-org",
    project: "my-project",
    include: "./dist",
    release: process.env.RELEASE,
  }),
]
```

## Data Retention

Default retention periods:
- **Errors**: 90 days
- **Transactions**: 90 days
- **Attachments**: 30 days
- **Replays**: 30 days

Adjust in Settings → General Settings → Data Retention.

## Security & Privacy

### Data Scrubbing
Sentry automatically scrubs:
- Passwords
- Credit card numbers
- API keys
- Session tokens

### GDPR Compliance
- User deletion API
- Data export functionality
- IP anonymization options
- Cookie consent handling

### Self-Hosted Benefits
- Complete data control
- No external data transmission
- Custom retention policies
- Compliance with regulations

## Performance Tuning

### Worker Scaling
```bash
# Scale workers based on load
kubectl scale deployment/sentry-worker -n sentry --replicas=4
```

### Database Optimization
```sql
-- Run periodic maintenance
VACUUM ANALYZE;

-- Monitor slow queries
SELECT * FROM pg_stat_statements ORDER BY total_time DESC;
```

### Redis Memory
Monitor Redis memory usage:
```bash
kubectl exec -n sentry deployment/sentry-redis -- redis-cli INFO memory
```

## Troubleshooting

### Check Component Health
```bash
# Web service logs
kubectl logs -n sentry deployment/sentry-web

# Worker logs
kubectl logs -n sentry deployment/sentry-worker

# Database connectivity
kubectl exec -n sentry deployment/sentry-web -- sentry shell
```

### Common Issues

1. **"CSRF Failed" Error**
   - Clear browser cookies
   - Check SECURE_PROXY_SSL_HEADER setting

2. **Events Not Appearing**
   - Verify DSN configuration
   - Check worker logs for processing errors
   - Ensure quota not exceeded

3. **Slow Performance**
   - Scale workers if queue backing up
   - Check PostgreSQL performance
   - Review retention settings

4. **Email Not Sending**
   - Verify SMTP configuration
   - Check email backend settings
   - Test with sentry shell

## Monitoring Sentry

### Prometheus Metrics
Sentry exposes metrics at `/metrics`:
```yaml
- job_name: sentry
  static_configs:
  - targets: ['sentry-web.sentry:9000']
```

Key metrics:
- `sentry_events_processed_total`
- `sentry_queue_depth`
- `sentry_worker_tasks_total`
- `sentry_api_requests_total`

## Backup Considerations

Critical data to backup:
1. PostgreSQL database
2. File storage (`/data/files`)
3. Configuration secrets

Backup script example:
```bash
# Database backup
kubectl exec -n sentry deployment/sentry-postgres -- \
  pg_dump -U sentry sentry > sentry-backup.sql

# Files backup
kubectl cp sentry/$(kubectl get pod -n sentry -l app=sentry-web -o jsonpath='{.items[0].metadata.name}'):/data/files ./sentry-files-backup
```