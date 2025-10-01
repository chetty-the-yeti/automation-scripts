#!/bin/bash

# Kill the mouse_move.sh process
pkill -f mouse_move.sh

# Kill the caffeinate process
pkill caffeinate

# Path to the image you want to display
IMAGE_PATH="/path/to/mouse_icon_off.png"

# Display a dialog box with an image
osascript <<EOF
display dialog "Mouse move script has been stopped" buttons {"OK"} default button "OK" with icon POSIX file "$IMAGE_PATH"
EOF