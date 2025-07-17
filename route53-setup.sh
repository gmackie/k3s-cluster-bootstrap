#!/bin/bash

# Route 53 DNS Setup for Gitea

DOMAIN="ci.yourdomain.com"
HOSTED_ZONE_ID="YOUR_ZONE_ID"
SERVER_IP="YOUR_SERVER_IP"

# Create A record
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "'$DOMAIN'",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$SERVER_IP'"}]
      }
    }]
  }'

# Optional: Add IPv6 if your VPS supports it
# aws route53 change-resource-record-sets \
#   --hosted-zone-id $HOSTED_ZONE_ID \
#   --change-batch '{
#     "Changes": [{
#       "Action": "UPSERT",
#       "ResourceRecordSet": {
#         "Name": "'$DOMAIN'",
#         "Type": "AAAA",
#         "TTL": 300,
#         "ResourceRecords": [{"Value": "YOUR_IPv6_ADDRESS"}]
#       }
#     }]
#   }'

echo "DNS updated. Changes may take 5-10 minutes to propagate."