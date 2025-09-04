#!/bin/bash

# Installation script for snappy-web-agent udev rules
# This script installs udev rules to allow non-root access to the snappy USB device

set -e

UDEV_RULES_FILE="99-snappy-web-agent.rules"
UDEV_RULES_DIR="/etc/udev/rules.d"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Check if udev rules file exists
if [ ! -f "${SCRIPT_DIR}/debian/${UDEV_RULES_FILE}" ]; then
    echo "Error: udev rules file not found at ${SCRIPT_DIR}/debian/${UDEV_RULES_FILE}"
    exit 1
fi

echo "Installing udev rules for snappy-web-agent..."

# Copy udev rules file
cp "${SCRIPT_DIR}/debian/${UDEV_RULES_FILE}" "${UDEV_RULES_DIR}/"
chmod 644 "${UDEV_RULES_DIR}/${UDEV_RULES_FILE}"

echo "Udev rules installed to ${UDEV_RULES_DIR}/${UDEV_RULES_FILE}"

# Reload udev rules
if command -v udevadm >/dev/null 2>&1; then
    echo "Reloading udev rules..."
    udevadm control --reload-rules
    udevadm trigger
    echo "Udev rules reloaded successfully"
else
    echo "Warning: udevadm not found. You may need to restart to apply the new rules."
fi

# Add user to dialout group if specified
if [ -n "$1" ]; then
    USERNAME="$1"
    if id "$USERNAME" &>/dev/null; then
        echo "Adding user $USERNAME to dialout group..."
        usermod -a -G dialout "$USERNAME"
        echo "User $USERNAME added to dialout group. Please log out and log back in for changes to take effect."
    else
        echo "Warning: User $USERNAME not found"
    fi
fi

echo "Installation complete!"
echo ""
echo "The snappy USB device (VID: 0xb1b0, PID: 0x5508) should now be accessible by:"
echo "- All users (with mode 666)"
echo "- Users in the dialout group"
echo ""
echo "If you specified a username, that user has been added to the dialout group."
echo "Please ensure the user logs out and logs back in for group changes to take effect."
echo ""
echo "You can now connect your snappy device and it should be detected by snappy-web-agent."
