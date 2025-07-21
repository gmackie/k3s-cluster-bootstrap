#!/bin/bash
# DNS Update Commands for Route 53

echo "=== DNS Configuration for gmac.io ==="
echo
echo "You need to add these DNS records in Route 53:"
echo
echo "1. Wildcard for all apps:"
echo "   Type: A"
echo "   Name: *.gmac.io" 
echo "   Value: 5.78.125.172"
echo "   TTL: 300"
echo
echo "2. Wildcard for staging:"
echo "   Type: A"
echo "   Name: staging-*"
echo "   Value: 5.78.125.172"
echo "   TTL: 300"
echo
echo "3. API subdomain (optional but recommended):"
echo "   Type: A"
echo "   Name: api"
echo "   Value: 5.78.125.172"
echo "   TTL: 300"
echo
echo "4. App subdomain (optional but recommended):"
echo "   Type: A"
echo "   Name: app"
echo "   Value: 5.78.125.172"
echo "   TTL: 300"
echo
echo "Current Setup:"
echo "- ci.gmac.io → 5.78.92.8 (Gitea CI/CD)"
echo "- *.gmac.io → 5.78.125.172 (K3s Apps)"
echo "- turntable.bot → 5.78.125.172 (K3s Apps)"
echo
echo "AWS CLI Commands (if you prefer):"
echo "Replace YOUR_ZONE_ID with your actual Route 53 hosted zone ID"
echo
cat << 'EOF'
# Get your zone ID
aws route53 list-hosted-zones --query "HostedZones[?Name=='gmac.io.'].Id" --output text

# Set zone ID
ZONE_ID="YOUR_ZONE_ID"

# Create wildcard A record
aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch '{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "*.gmac.io",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "5.78.125.172"}]
    }
  }]
}'

# Create staging wildcard
aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch '{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "staging-*.gmac.io",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "5.78.125.172"}]
    }
  }]
}'
EOF