#!/bin/bash

# Backup Gitea to S3 (no volume needed)

BACKUP_DIR="/tmp/gitea-backup"
S3_BUCKET="s3://your-backup-bucket/gitea"
DATE=$(date +%Y%m%d-%H%M%S)

# Create backup
mkdir -p $BACKUP_DIR
cd $BACKUP_DIR

# Backup Gitea data
docker exec -u git gitea sh -c 'gitea dump -c /data/gitea/conf/app.ini' || \
    /usr/local/bin/gitea dump -c /etc/gitea/app.ini

# Upload to S3
aws s3 cp gitea-dump-*.zip $S3_BUCKET/backup-$DATE.zip

# Keep only last 7 days
aws s3 ls $S3_BUCKET/ | while read -r line; do
    createDate=$(echo $line | awk '{print $1" "$2}')
    createDate=$(date -d "$createDate" +%s)
    olderThan=$(date -d "7 days ago" +%s)
    if [[ $createDate -lt $olderThan ]]; then
        fileName=$(echo $line | awk '{print $4}')
        aws s3 rm $S3_BUCKET/$fileName
    fi
done

# Cleanup
rm -rf $BACKUP_DIR

echo "Backup completed: $S3_BUCKET/backup-$DATE.zip"