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
echo "This will back up files from your Mac Mini to the NFS share."
read -p "Are you sure you want to continue? (yes/no): " CONFIRM_1

if [[ "$CONFIRM_1" != "yes" ]]; then
    echo "Backup operation canceled."
    exit 0
fi

# Ask for confirmation again
read -p "Are you really sure you want to continue? (yes/no): " CONFIRM_2

if [[ "$CONFIRM_2" != "yes" ]]; then
    echo "Backup operation canceled."
    exit 0
fi

# Loop through each source folder and back it up to the NFS destination
for SOURCE in "${SOURCE_FOLDERS[@]}"; do
    if [[ "$SOURCE" == *"App2/Saves"* ]]; then
        # Backup to the separate App2 folder
        DEST_PATH="$DEST_FOLDER_APP2/$(basename "$SOURCE")"
    else
        # Backup to the main backup folder
        DEST_PATH="$DEST_FOLDER_MAIN/$(basename "$SOURCE")"
    fi

    # Check if the source directory exists
    if [ ! -d "$SOURCE" ]; then
        echo "ERROR: Source folder $SOURCE does not exist. Skipping."
        continue
    else
        echo "Source folder found: $SOURCE"
    fi

    # Check if the destination directory exists, if not, create it
    if [ ! -d "$DEST_PATH" ]; then
        echo "Destination directory $DEST_PATH does not exist. Creating it..."
        mkdir -p "$DEST_PATH"
    fi

    # Back up the source folder to the destination with progress
    echo "Backing up from $SOURCE to $DEST_PATH"
    rsync -av --delete --progress --modify-window=1 "$SOURCE/" "$DEST_PATH/"
done

echo "Backup operation completed."
# End of script
