#!/bin/bash

# Path to the image you want to display (update this path to your image file)
IMAGE_PATH="/path/to/mouse_icon.png"

# Display a dialog box with an image
osascript <<EOF
display dialog "Mouse move script is now running" buttons {"OK"} default button "OK" with icon POSIX file "$IMAGE_PATH"
EOF

# Prevent the system from sleeping
caffeinate -dims &

# Infinite loop to move the mouse every 1 minute
while true; do
    # Move the mouse slightly
    cliclick m:+10,+10
    sleep 1
    cliclick m:-10,-10
    
    # Wait for 1 minute
    sleep 60
done