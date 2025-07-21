# DNS Configuration for K3s

## Required DNS Records

Add these records to your Route 53 hosted zone for gmac.io:

### Wildcard Records for Apps

```
Type: A
Name: *.k3s
Value: 5.78.92.8
TTL: 300

Type: A  
Name: staging-*
Value: 5.78.92.8
TTL: 300
```

### Specific App Records (optional, but recommended)

```
Type: A
Name: api
Value: 5.78.92.8
TTL: 300

Type: A
Name: app
Value: 5.78.92.8
TTL: 300
```

## AWS CLI Commands

If you prefer using AWS CLI:

```bash
# Get your hosted zone ID first
aws route53 list-hosted-zones --query "HostedZones[?Name=='gmac.io.'].Id" --output text

# Replace ZONE_ID with your actual zone ID
ZONE_ID="your-zone-id-here"

# Create wildcard record for k3s apps
aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch '{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "*.k3s.gmac.io",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "5.78.92.8"}]
    }
  }]
}'

# Create wildcard record for staging
aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch '{
  "Changes": [{
    "Action": "CREATE", 
    "ResourceRecordSet": {
      "Name": "staging-*.gmac.io",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "5.78.92.8"}]
    }
  }]
}'
```

## Testing DNS

After adding records, test with:

```bash
# Should resolve to 5.78.92.8
dig test.k3s.gmac.io
dig staging-pr-123.gmac.io
```

## URL Structure

Your apps will be accessible at:

- **Production**: `https://appname.gmac.io` or `https://app.k3s.gmac.io`
- **Staging PRs**: `https://staging-pr-123.gmac.io`
- **Feature branches**: `https://staging-feature-xyz.gmac.io`