#!/bin/bash

# Snappy Web Agent Uninstaller

BUNDLE_ID="com.snappy.webagent"
APP_NAME="snappy-web-agent"
PLIST_PATH="/Library/LaunchDaemons/$BUNDLE_ID.plist"

echo "Uninstalling Snappy Web Agent..."

# Stop and unload daemon
if launchctl list | grep -q "$BUNDLE_ID"; then
    echo "Stopping daemon..."
    sudo launchctl stop "$BUNDLE_ID"
    sudo launchctl unload "$PLIST_PATH"
    echo "✓ Daemon stopped"
fi

# Remove files
echo "Removing files..."
sudo rm -f "/usr/local/bin/$APP_NAME"
sudo rm -f "$PLIST_PATH"
sudo rm -rf "/usr/local/share/$APP_NAME"
sudo rm -rf "/var/log/$APP_NAME"

echo "✓ Snappy Web Agent has been uninstalled"
echo "✓ All files and services have been removed"
