#!/bin/bash

POLICY_SRC="$(dirname "$0")/policies/managed"
POLICY_DEST="/etc/chromium/policies/managed"

# Check if ungoogled-chromium is installed
if ! pacman -Q 2>/dev/null | grep -q "ungoogled-chromium"; then
    echo "ungoogled-chromium is not installed. Skipping policy install."
    exit 0
fi

echo "Detected ungoogled-chromium. Installing policies..."

if [ ! -d "$POLICY_SRC" ]; then
    echo "Error: Source policies not found at $POLICY_SRC"
    exit 1
fi

sudo mkdir -p "$POLICY_DEST"
sudo cp "$POLICY_SRC"/*.json "$POLICY_DEST/"
sudo chmod -R 755 /etc/chromium/policies/

echo "Policies installed to $POLICY_DEST:"
ls -la "$POLICY_DEST"
echo ""
echo "Restart Chromium and check chrome://policy to verify."
