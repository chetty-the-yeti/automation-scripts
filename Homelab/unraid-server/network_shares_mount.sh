#!/bin/bash

# Wait for network and array to initialize
sleep 10

SERVER="NAS_SERVER_IP" # Replace with your NAS server IP
LOCAL_BASE="/mnt/remotes"
SHARES=(
  "software"
  "data"
  "photos"
  "backups"
  "isos"
  # Add more share names as needed
)

echo "Starting dynamic NFS mount script..."

# Get export list from the NAS
EXPORTS=$(showmount -e $SERVER | tail -n +2 | awk '{print $1}')

for SHARE in "${SHARES[@]}"; do
    # Find the export path that ends with the share name
    REMOTE_PATH=$(echo "$EXPORTS" | grep "/${SHARE}/.data$")

    if [ -z "$REMOTE_PATH" ]; then
        echo "❌ Export for '${SHARE}' not found on $SERVER"
        continue
    fi

    LOCAL_PATH="${LOCAL_BASE}/${SHARE}"
    mkdir -p "$LOCAL_PATH"

    if mountpoint -q "$LOCAL_PATH"; then
        echo "  ↪ Already mounted: $LOCAL_PATH"
        continue
    fi

    echo "→ Mounting '${SHARE}' from $REMOTE_PATH to $LOCAL_PATH..."
    mount -t nfs -o nfsvers=3 "$SERVER:$REMOTE_PATH" "$LOCAL_PATH"

    if mountpoint -q "$LOCAL_PATH"; then
        echo "  ✅ Mounted: $LOCAL_PATH"
    else
        echo "  ❌ Failed: $LOCAL_PATH (check NFS settings)"
    fi

    sleep 1
done

echo "✅ Dynamic NFS mount script completed."