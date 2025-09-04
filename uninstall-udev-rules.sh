#!/bin/bash

# Uninstallation script for snappy-web-agent udev rules
# This script removes udev rules for the snappy USB device

set -e

UDEV_RULES_FILE="99-snappy-web-agent.rules"
UDEV_RULES_DIR="/etc/udev/rules.d"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

echo "Removing udev rules for snappy-web-agent..."

# Remove udev rules file if it exists
if [ -f "${UDEV_RULES_DIR}/${UDEV_RULES_FILE}" ]; then
    rm -f "${UDEV_RULES_DIR}/${UDEV_RULES_FILE}"
    echo "Udev rules removed from ${UDEV_RULES_DIR}/${UDEV_RULES_FILE}"
else
    echo "Udev rules file not found, nothing to remove"
fi

# Reload udev rules
if command -v udevadm >/dev/null 2>&1; then
    echo "Reloading udev rules..."
    udevadm control --reload-rules
    udevadm trigger
    echo "Udev rules reloaded successfully"
else
    echo "Warning: udevadm not found. You may need to restart for changes to take effect."
fi

echo "Uninstallation complete!"
echo ""
echo "Note: This script does not remove users from the dialout group."
echo "If you want to remove a user from the dialout group, run:"
echo "sudo gpasswd -d <username> dialout"
