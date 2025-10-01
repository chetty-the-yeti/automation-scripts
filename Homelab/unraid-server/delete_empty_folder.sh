#!/bin/bash
echo "Searching for (and deleting) Folders under 10MB"
echo "This may take a while"
while IFS= read -r folder; do
    folder_size=$(du -s "$folder" | awk '{print $1}')
    if [ "$folder_size" -lt 10240 ]; then
        rm -rf "$folder"
        echo "Deleted: $folder"
    fi
done < <(find /mnt/remotes/SHARE_NAME/ -mindepth 1 -type d) # Replace SHARE_NAME with your share