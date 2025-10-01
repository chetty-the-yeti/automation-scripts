#!/bin/bash

# Define source folders
SOURCE_FOLDERS=(
    "/Users/yourusername/Library/Application Support/App1"
    "/Users/yourusername/Local Storage/Data"
    "/Users/yourusername/Library/Application Support/App2/Saves"
)

# Define destination folders
DEST_FOLDER_MAIN="/path/to/backups/Main"
DEST_FOLDER_APP2="/path/to/backups/App2"

# Ensure the backup share is mounted
if ! mount | grep -q "/path/to/backups"; then
    echo "ERROR: Backup share not mounted at /path/to/backups. Please check your mount."
    exit 1
else  
    echo "Backup share mounted successfully at /path/to/backups."
fi

# Ask for confirmation
echo "This will restore backups from the backup share to their original locations."
read -p "Are you sure you want to continue? (yes/no): " CONFIRM_1

if [[ "$CONFIRM_1" != "yes" ]]; then
    echo "Restore operation canceled."
    exit 0
fi

# Ask for confirmation again
read -p "Are you really sure you want to continue? (yes/no): " CONFIRM_2

if [[ "$CONFIRM_2" != "yes" ]]; then
    echo "Restore operation canceled."
    exit 0
fi

# Loop through each source folder and restore it from the backup
for SOURCE in "${SOURCE_FOLDERS[@]}"; do
    if [[ "$SOURCE" == *"App2/Saves"* ]]; then
        # Restore from the separate App2 folder
        DEST_PATH="$DEST_FOLDER_APP2/$(basename "$SOURCE")"
    else
        # Restore from the main backup folder
        DEST_PATH="$DEST_FOLDER_MAIN/$(basename "$SOURCE")"
    fi

    # Check if the destination backup folder exists
    if [ ! -d "$DEST_PATH" ]; then
        echo "ERROR: Backup folder $DEST_PATH does not exist. Skipping."
        continue
    else
        echo "Backup folder found: $DEST_PATH"
    fi

    # Check if the source directory exists, if not, create it
    if [ ! -d "$SOURCE" ]; then
        echo "Directory $SOURCE does not exist. Creating it..."
        mkdir -p "$SOURCE"
    fi

    # Restore the backup to the source folder with progress
    echo "Restoring from $DEST_PATH to $SOURCE"
    rsync -av --delete --progress "$DEST_PATH/" "$SOURCE/"
done

echo "Restore operation completed."
