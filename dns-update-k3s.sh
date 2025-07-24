#!/bin/bash
# DNS Update Script for K3s Dashboard
# Updates Route 53 DNS records to point k3s.gmac.io to your server

set -e

SERVER_IP="5.78.92.8"  # Your CI server IP (where k3s will run)
HOSTED_ZONE_ID="Z1234567890ABC"  # Replace with your actual hosted zone ID

echo "=== DNS Update for K3s Dashboard ==="
echo "This will create/update DNS records for k3s.gmac.io"
echo "Server IP: $SERVER_IP"
echo

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first:"
    echo "brew install awscli"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured. Please run:"
    echo "aws configure"
    exit 1
fi

echo "✅ AWS CLI is configured"

# Get the hosted zone ID for gmac.io
echo "Finding hosted zone for gmac.io..."
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='gmac.io.'].Id" --output text | cut -d'/' -f3)

if [ -z "$HOSTED_ZONE_ID" ]; then
    echo "Error: Could not find hosted zone for gmac.io"
    echo "Please check your AWS account and domain configuration."
    exit 1
fi

echo "✅ Found hosted zone: $HOSTED_ZONE_ID"

# Create change batch JSON
CHANGE_BATCH=$(cat <<EOF
{
    "Comment": "Add k3s dashboard subdomain",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "k3s.gmac.io",
                "Type": "A",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "$SERVER_IP"
                    }
                ]
            }
        }
    ]
}
EOF
)

# Apply the DNS change
echo "Creating DNS record for k3s.gmac.io..."
CHANGE_ID=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "$CHANGE_BATCH" \
    --query 'ChangeInfo.Id' \
    --output text)

echo "✅ DNS change submitted: $CHANGE_ID"

# Wait for change to propagate
echo "Waiting for DNS change to propagate..."
aws route53 wait resource-record-sets-changed --id "$CHANGE_ID"

echo "✅ DNS change completed"

# Verify the DNS record
echo "Verifying DNS record..."
sleep 10  # Give DNS a moment to propagate

if nslookup k3s.gmac.io | grep -q "$SERVER_IP"; then
    echo "✅ DNS record verified: k3s.gmac.io → $SERVER_IP"
else
    echo "⚠️  DNS record may still be propagating. Please wait a few minutes and try:"
    echo "nslookup k3s.gmac.io"
fi

echo
echo "=== DNS Update Complete ==="
echo "k3s.gmac.io now points to $SERVER_IP"
echo
echo "You can now proceed with the dashboard setup:"
echo "./setup-k3s-dashboard.sh"