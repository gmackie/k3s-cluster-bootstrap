#!/bin/bash

# Add Hetzner Volume to existing server (if needed later)

SERVER_NAME="gitea-ci"
VOLUME_SIZE="100"  # GB

# Create volume
hcloud volume create \
    --size $VOLUME_SIZE \
    --name gitea-data \
    --location ash

# Attach to server
hcloud volume attach gitea-data --server $SERVER_NAME

# Mount on server
ssh root@$(hcloud server ip $SERVER_NAME) << 'EOF'
# Format and mount volume
mkfs.ext4 /dev/disk/by-id/scsi-0HC_Volume_*
mkdir -p /mnt/gitea-data

# Add to fstab
echo "/dev/disk/by-id/scsi-0HC_Volume_* /mnt/gitea-data ext4 defaults,nofail 0 0" >> /etc/fstab
mount -a

# Move Gitea data to volume
systemctl stop gitea
mv /var/lib/gitea/data /mnt/gitea-data/
ln -s /mnt/gitea-data/data /var/lib/gitea/data
systemctl start gitea

echo "Volume mounted and Gitea data migrated!"
EOF