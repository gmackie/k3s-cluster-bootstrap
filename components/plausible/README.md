# Plausible Analytics Component

This component installs Plausible Analytics, a lightweight and privacy-friendly web analytics tool.

## Features

- **Privacy-First**: No cookies, GDPR/CCPA compliant by default
- **Lightweight**: <1KB tracking script
- **Real-Time**: See your visitors in real-time
- **Simple**: Clean, intuitive dashboard
- **Open Source**: Self-hosted with full data ownership
- **No Personal Data**: No tracking across sites or devices
- **Custom Events**: Track goals and conversions
- **API Access**: Export and integrate your data

## Architecture

- Plausible application server
- PostgreSQL for user data and settings
- ClickHouse for efficient analytics storage
- No external dependencies or third-party services

## Access

- **Dashboard**: `https://analytics.<domain>`
- **Tracking Script**: `https://analytics.<domain>/js/script.js`
- **API Endpoint**: `https://analytics.<domain>/api/v1/`

Dashboard access is protected by OAuth2, while tracking endpoints are public.

## Quick Start

### 1. Login to Dashboard
```
URL: https://analytics.<domain>
Email: admin@<domain>
Password: <from credentials file>
```

### 2. Add Your First Site
1. Click "Add Website"
2. Enter your domain (e.g., `example.com`)
3. Choose timezone
4. Copy the tracking snippet

### 3. Add Tracking Script
Add to your website's `<head>` tag:
```html
<script defer data-domain="example.com" src="https://analytics.<domain>/js/script.js"></script>
```

### 4. Verify Installation
Visit your website and check the Plausible dashboard for real-time visitors.

## Tracking Script Options

### Standard Tracking
```html
<script defer data-domain="example.com" src="https://analytics.<domain>/js/script.js"></script>
```

### With Custom Events
```html
<script defer data-domain="example.com" src="https://analytics.<domain>/js/script.tagged-events.js"></script>
```

### Track Outbound Links
```html
<script defer data-domain="example.com" src="https://analytics.<domain>/js/script.outbound-links.js"></script>
```

### Track File Downloads
```html
<script defer data-domain="example.com" src="https://analytics.<domain>/js/script.file-downloads.js"></script>
```

### For Hash-Based Routing (SPAs)
```html
<script defer data-domain="example.com" src="https://analytics.<domain>/js/script.hash.js"></script>
```

### Combined Features
```html
<script defer data-domain="example.com" src="https://analytics.<domain>/js/script.tagged-events.outbound-links.js"></script>
```

## Custom Events

Track conversions, goals, and custom events:

### JavaScript API
```javascript
// Track a goal
plausible('Signup')

// Track with custom properties
plausible('Download', {props: {file: 'ebook.pdf', category: 'resources'}})

// Track revenue
plausible('Purchase', {revenue: {amount: 29.99, currency: 'USD'}})
```

### Form Submissions
```html
<form onsubmit="plausible('Contact Form Submitted')">
  <!-- form fields -->
</form>
```

### Button Clicks
```html
<button onclick="plausible('CTA Clicked', {props: {location: 'header'}})">
  Get Started
</button>
```

## Goals and Conversions

1. Go to Site Settings → Goals
2. Add goal (e.g., "Signup", "Purchase", "Download")
3. Track via custom events or page views
4. View conversion rates in dashboard

## API Access

### Generate API Key
1. Go to Settings → API Keys
2. Create new key with desired permissions
3. Use Bearer token authentication

### Example API Calls

#### Get Aggregate Stats
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
  "https://analytics.<domain>/api/v1/stats/aggregate?site_id=example.com&period=7d&metrics=visitors,pageviews,bounce_rate,visit_duration"
```

#### Get Top Pages
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
  "https://analytics.<domain>/api/v1/stats/breakdown?site_id=example.com&period=7d&property=event:page&limit=10"
```

#### Get Sources
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
  "https://analytics.<domain>/api/v1/stats/breakdown?site_id=example.com&period=7d&property=visit:source"
```

#### Export Data
```bash
# Timeseries data
curl -H "Authorization: Bearer YOUR_API_KEY" \
  "https://analytics.<domain>/api/v1/stats/timeseries?site_id=example.com&period=30d"
```

## Email Reports

1. Go to Site Settings → Email Reports
2. Choose frequency (Weekly/Monthly)
3. Add recipient emails
4. Select report content

## Google Search Console Integration

1. Go to Site Settings → Search Console
2. Follow Google OAuth flow
3. Select your property
4. View search queries in dashboard

## Excluding Internal Traffic

### By IP Address
1. Site Settings → Shields
2. Add IP addresses to exclude

### By Script
Use the exclusions script:
```html
<script defer data-domain="example.com" src="https://analytics.<domain>/js/script.exclusions.js"></script>
```

Then localStorage flag:
```javascript
localStorage.plausible_ignore = true
```

## Data Retention

- Default: Unlimited
- Can be configured per site
- Data is stored in ClickHouse for efficiency
- No personal data is ever collected

## Privacy Features

### What's NOT Collected
- No cookies used
- No personal data
- No device fingerprinting
- No cross-site tracking
- No IP address storage (only country)

### GDPR Compliance
- No consent banner needed
- Right to deletion (delete site = delete data)
- Data portability (API export)
- Privacy by design

## Performance

### Script Loading
- Served from same domain (no third-party requests)
- <1KB gzipped
- Async/defer loading
- No impact on page speed

### Server Performance
- ClickHouse handles millions of events
- Real-time processing
- Efficient data aggregation
- Low resource usage

## Troubleshooting

### No Data Showing
1. Verify script is installed correctly
2. Check browser console for errors
3. Ensure data-domain matches exactly
4. Disable ad blockers for testing
5. Wait 5 minutes for data to appear

### Script Blocked
Some ad blockers block "analytics" domains. Solutions:
1. Proxy the script through your domain
2. Self-host the script file
3. Use a custom subdomain

### Custom Events Not Working
1. Use tagged-events script variant
2. Check event name format (no spaces)
3. Verify plausible function is available
4. Check browser console for errors

### API Issues
1. Verify API key permissions
2. Check site_id parameter
3. Use correct date formats
4. Check rate limits (600 requests/hour)

## Advanced Configuration

### Proxy Setup
To avoid ad blockers, proxy through your domain:

```nginx
location /js/script.js {
    proxy_pass https://analytics.<domain>/js/script.js;
    proxy_set_header Host analytics.<domain>;
}

location /api/event {
    proxy_pass https://analytics.<domain>/api/event;
    proxy_set_header Host analytics.<domain>;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

### Multiple Domains
Track multiple domains with one script:
```html
<script defer data-domain="example.com,app.example.com" src="https://analytics.<domain>/js/script.js"></script>
```

### Development Exclusion
Exclude localhost tracking:
```javascript
if (window.location.hostname !== 'localhost') {
    // Add Plausible script
}
```

## Backup

### Database Backup
```bash
# PostgreSQL (settings, users)
kubectl exec -n plausible deployment/plausible-postgres -- \
  pg_dump -U plausible plausible > plausible-backup.sql

# ClickHouse (analytics data)
kubectl exec -n plausible deployment/plausible-clickhouse -- \
  clickhouse-client --query "BACKUP DATABASE plausible TO File('/backup/plausible')"
```

### Restore Process
1. Deploy fresh Plausible
2. Restore PostgreSQL data
3. Restore ClickHouse data
4. Verify site configurations

## Integration Examples

### React/Next.js
```jsx
import { useEffect } from 'react'
import { useRouter } from 'next/router'

export default function MyApp({ Component, pageProps }) {
  const router = useRouter()

  useEffect(() => {
    const handleRouteChange = () => plausible('pageview')
    router.events.on('routeChangeComplete', handleRouteChange)
    return () => router.events.off('routeChangeComplete', handleRouteChange)
  }, [router.events])

  return <Component {...pageProps} />
}
```

### Vue.js
```javascript
// main.js
import { createApp } from 'vue'
import Plausible from 'plausible-tracker'

const plausible = Plausible({
  domain: 'example.com',
  apiHost: 'https://analytics.<domain>'
})

app.config.globalProperties.$plausible = plausible
app.provide('plausible', plausible)
```

### WordPress
```php
// functions.php
function add_plausible_analytics() {
    ?>
    <script defer data-domain="<?php echo $_SERVER['HTTP_HOST']; ?>" 
            src="https://analytics.<?php echo DOMAIN; ?>/js/script.js"></script>
    <?php
}
add_action('wp_head', 'add_plausible_analytics');
```