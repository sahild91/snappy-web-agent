#!/bin/bash

# Snappy Web Agent - macOS Universal Build Script
# Creates ARM64 and x86_64 binaries, combines them into a universal binary,
# and packages everything into a PKG installer with launchd daemon setup

set -euo pipefail

# Configuration
APP_NAME="snappy-web-agent"
APP_VERSION="0.1.0"
BUNDLE_ID="com.snappy.webagent"
BUILD_DIR="build"
DIST_DIR="dist"
PKG_DIR="pkg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v cargo &> /dev/null; then
        error "Cargo is not installed. Please install Rust."
    fi
    
    if ! command -v pkgbuild &> /dev/null; then
        error "pkgbuild is not available. This script requires macOS."
    fi
    
    if ! command -v productbuild &> /dev/null; then
        error "productbuild is not available. This script requires macOS."
    fi
    
    success "All dependencies found"
}

# Add Rust targets
add_targets() {
    log "Adding Rust targets for cross-compilation..."
    rustup target add aarch64-apple-darwin
    rustup target add x86_64-apple-darwin
    success "Rust targets added"
}

# Clean previous builds
clean_build() {
    log "Cleaning previous builds..."
    rm -rf target/aarch64-apple-darwin/release/$APP_NAME
    rm -rf target/x86_64-apple-darwin/release/$APP_NAME
    rm -rf $BUILD_DIR
    rm -rf $DIST_DIR
    rm -rf $PKG_DIR
    cargo clean
    success "Clean completed"
}

# Build for ARM64 (Apple Silicon)
build_arm64() {
    log "Building for ARM64 (Apple Silicon)..."
    cargo build --release --target aarch64-apple-darwin
    success "ARM64 build completed"
}

# Build for x86_64 (Intel)
build_x86_64() {
    log "Building for x86_64 (Intel)..."
    cargo build --release --target x86_64-apple-darwin
    success "x86_64 build completed"
}

# Create universal binary
create_universal_binary() {
    log "Creating universal binary..."
    
    mkdir -p $BUILD_DIR
    
    lipo -create \
        target/aarch64-apple-darwin/release/$APP_NAME \
        target/x86_64-apple-darwin/release/$APP_NAME \
        -output $BUILD_DIR/$APP_NAME
    
    # Verify the universal binary
    file $BUILD_DIR/$APP_NAME
    lipo -info $BUILD_DIR/$APP_NAME
    
    success "Universal binary created"
}

# Create installation directory structure
create_install_structure() {
    log "Creating installation directory structure..."
    
    mkdir -p $DIST_DIR/usr/local/bin
    mkdir -p $DIST_DIR/Library/LaunchDaemons
    mkdir -p $DIST_DIR/usr/local/share/$APP_NAME
    mkdir -p $DIST_DIR/var/log/$APP_NAME
    
    # Copy binary
    cp $BUILD_DIR/$APP_NAME $DIST_DIR/usr/local/bin/
    chmod +x $DIST_DIR/usr/local/bin/$APP_NAME
    
    # Copy README and other docs
    cp README.md $DIST_DIR/usr/local/share/$APP_NAME/
    
    success "Installation structure created"
}

# Create launchd plist
create_launchd_plist() {
    log "Creating launchd configuration..."
    
    cat > $DIST_DIR/Library/LaunchDaemons/$BUNDLE_ID.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/$APP_NAME</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>
    
    <key>StandardOutPath</key>
    <string>/var/log/$APP_NAME/stdout.log</string>
    
    <key>StandardErrorPath</key>
    <string>/var/log/$APP_NAME/stderr.log</string>
    
    <key>WorkingDirectory</key>
    <string>/usr/local/share/$APP_NAME</string>
    
    <key>UserName</key>
    <string>root</string>
    
    <key>GroupName</key>
    <string>wheel</string>
    
    <key>ProcessType</key>
    <string>Background</string>
    
    <key>ThrottleInterval</key>
    <integer>10</integer>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
EOF
    
    success "Launchd plist created"
}

# Create postinstall script
create_postinstall_script() {
    log "Creating postinstall script..."
    
    mkdir -p $PKG_DIR/scripts
    
    cat > $PKG_DIR/scripts/postinstall << 'EOF'
#!/bin/bash

# Snappy Web Agent Post-Install Script

BUNDLE_ID="com.snappy.webagent"
APP_NAME="snappy-web-agent"
PLIST_PATH="/Library/LaunchDaemons/$BUNDLE_ID.plist"

echo "Configuring Snappy Web Agent daemon..."

# Set proper permissions
chown root:wheel "/usr/local/bin/$APP_NAME"
chmod 755 "/usr/local/bin/$APP_NAME"

# Set permissions for plist
chown root:wheel "$PLIST_PATH"
chmod 644 "$PLIST_PATH"

# Create log directory with proper permissions
mkdir -p "/var/log/$APP_NAME"
chown root:wheel "/var/log/$APP_NAME"
chmod 755 "/var/log/$APP_NAME"

# Load the daemon
echo "Loading daemon..."
if launchctl load "$PLIST_PATH"; then
    echo "✓ Daemon loaded successfully"
else
    echo "⚠ Warning: Failed to load daemon"
fi

# Start the daemon
echo "Starting daemon..."
if launchctl start "$BUNDLE_ID"; then
    echo "✓ Daemon started successfully"
    echo "✓ Snappy Web Agent is now running in the background"
    echo "✓ It will automatically start on system boot"
else
    echo "⚠ Warning: Failed to start daemon"
fi

# Show status
echo ""
echo "Daemon status:"
launchctl list | grep "$BUNDLE_ID" || echo "Daemon not found in list"

echo ""
echo "Installation completed!"
echo "The Snappy Web Agent is now running as a background service."
echo "It will automatically start whenever the system boots."
echo ""
echo "To check logs:"
echo "  tail -f /var/log/$APP_NAME/stdout.log"
echo "  tail -f /var/log/$APP_NAME/stderr.log"
echo ""
echo "To manually control the service:"
echo "  sudo launchctl stop $BUNDLE_ID"
echo "  sudo launchctl start $BUNDLE_ID"
echo "  sudo launchctl unload $PLIST_PATH"

exit 0
EOF
    
    chmod +x $PKG_DIR/scripts/postinstall
    success "Postinstall script created"
}

# Create preinstall script
create_preinstall_script() {
    log "Creating preinstall script..."
    
    mkdir -p $PKG_DIR/scripts
    
    cat > $PKG_DIR/scripts/preinstall << 'EOF'
#!/bin/bash

# Snappy Web Agent Pre-Install Script

BUNDLE_ID="com.snappy.webagent"
PLIST_PATH="/Library/LaunchDaemons/$BUNDLE_ID.plist"

echo "Preparing for Snappy Web Agent installation..."

# Stop existing daemon if running
if launchctl list | grep -q "$BUNDLE_ID"; then
    echo "Stopping existing daemon..."
    launchctl stop "$BUNDLE_ID" 2>/dev/null || true
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    echo "✓ Existing daemon stopped"
fi

exit 0
EOF
    
    chmod +x $PKG_DIR/scripts/preinstall
    success "Preinstall script created"
}

# Create component package
create_component_package() {
    log "Creating component package..."
    
    mkdir -p $PKG_DIR/component
    
    pkgbuild \
        --root $DIST_DIR \
        --scripts $PKG_DIR/scripts \
        --identifier $BUNDLE_ID \
        --version $APP_VERSION \
        --install-location / \
        $PKG_DIR/component/$APP_NAME-component.pkg
    
    success "Component package created"
}

# Create distribution XML
create_distribution_xml() {
    log "Creating distribution XML..."
    
    cat > $PKG_DIR/distribution.xml << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>Snappy Web Agent</title>
    <organization>$BUNDLE_ID</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true"/>
    
    <!-- Define documents displayed at various steps -->
    <welcome    file="welcome.html"/>
    <license    file="license.html"/>
    <conclusion file="conclusion.html"/>
    
    <!-- List all component packages -->
    <pkg-ref id="$BUNDLE_ID" version="$APP_VERSION">$APP_NAME-component.pkg</pkg-ref>
    
    <!-- List them again here. They can now be organized
         as a hierarchy if you want. -->
    <choices-outline>
        <line choice="default">
            <line choice="$BUNDLE_ID"/>
        </line>
    </choices-outline>
    
    <!-- Define the choice items -->
    <choice id="default"/>
    <choice id="$BUNDLE_ID" visible="false">
        <pkg-ref id="$BUNDLE_ID"/>
    </choice>
</installer-gui-script>
EOF
    
    success "Distribution XML created"
}

# Create installer resources
create_installer_resources() {
    log "Creating installer resources..."
    
    mkdir -p $PKG_DIR/resources
    
    # Welcome page
    cat > $PKG_DIR/resources/welcome.html << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Welcome</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 20px; }
        h1 { color: #1d1d1f; }
        p { color: #515154; line-height: 1.5; }
    </style>
</head>
<body>
    <h1>Welcome to Snappy Web Agent</h1>
    <p>This installer will install Snappy Web Agent on your Mac.</p>
    <p>Snappy Web Agent is a Rust-based web agent for collecting and streaming data from serial devices via Socket.IO.</p>
    <p><strong>Features:</strong></p>
    <ul>
        <li>Dynamic port selection</li>
        <li>Encrypted communication</li>
        <li>Real-time Socket.IO integration</li>
        <li>Automatic background service</li>
    </ul>
    <p>The application will be installed as a background service that starts automatically on system boot.</p>
</body>
</html>
EOF
    
    # License page
    cat > $PKG_DIR/resources/license.html << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>License</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 20px; }
        h1 { color: #1d1d1f; }
        p { color: #515154; line-height: 1.5; }
    </style>
</head>
<body>
    <h1>Software License Agreement</h1>
    <p>Please read and accept the following license agreement:</p>
    <div style="padding: 15px; border-radius: 8px; font-family: monospace; font-size: 12px;">
        <p>Copyright (c) 2025 YuduRobotics</p>
        <p>Permission is hereby granted to use this software for its intended purpose.</p>
        <p>This software is provided "as is" without warranty of any kind.</p>
    </div>
</body>
</html>
EOF
    
    # Conclusion page
    cat > $PKG_DIR/resources/conclusion.html << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Installation Complete</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 20px; }
        h1 { color: #1d1d1f; }
        p { color: #515154; line-height: 1.5; }
        .success { color: #30a46c; font-weight: bold; }
        .code { padding: 10px; border-radius: 4px; font-family: monospace; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Installation Complete!</h1>
    <p class="success">✓ Snappy Web Agent has been successfully installed and started.</p>
    
    <h2>What's Next?</h2>
    <p>The Snappy Web Agent is now running as a background service and will automatically start on system boot.</p>
    
    <h2>Service Management</h2>
    <p>To manage the service, use these commands in Terminal:</p>
    <div class="code">
# Check service status<br>
sudo launchctl list | grep com.snappy.webagent<br><br>

# Stop the service<br>
sudo launchctl stop com.snappy.webagent<br><br>

# Start the service<br>
sudo launchctl start com.snappy.webagent<br><br>

# View logs<br>
tail -f /var/log/snappy-web-agent/stdout.log
    </div>
    
    <h2>Connecting</h2>
    <p>The agent will be available on the first available port starting from 8436. Check the logs to see which port it's using.</p>
</body>
</html>
EOF
    
    success "Installer resources created"
}

# Create final installer package
create_final_package() {
    log "Creating final installer package..."
    
    productbuild \
        --distribution $PKG_DIR/distribution.xml \
        --package-path $PKG_DIR/component \
        --resources $PKG_DIR/resources \
        $APP_NAME-$APP_VERSION-universal.pkg
    
    success "Final installer package created: $APP_NAME-$APP_VERSION-universal.pkg"
}

# Create uninstaller script
create_uninstaller() {
    log "Creating uninstaller script..."
    
    cat > uninstall_${APP_NAME}.sh << 'EOF'
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
EOF
    
    chmod +x uninstall_${APP_NAME}.sh
    success "Uninstaller created: uninstall_${APP_NAME}.sh"
}

# Display build summary
show_summary() {
    log "Build Summary"
    echo "=============================================="
    echo "✓ Universal binary: $BUILD_DIR/$APP_NAME"
    echo "✓ Installer package: $APP_NAME-$APP_VERSION-universal.pkg"
    echo "✓ Uninstaller script: uninstall_${APP_NAME}.sh"
    echo ""
    echo "Binary architecture:"
    lipo -info $BUILD_DIR/$APP_NAME
    echo ""
    echo "Package size:"
    ls -lh $APP_NAME-$APP_VERSION-universal.pkg
    echo ""
    echo "To install: Double-click the .pkg file or run:"
    echo "  sudo installer -pkg $APP_NAME-$APP_VERSION-universal.pkg -target /"
    echo ""
    echo "To uninstall: Run the uninstaller script:"
    echo "  sudo ./uninstall_${APP_NAME}.sh"
    echo "=============================================="
}

# Main execution
main() {
    log "Starting macOS universal build process..."
    
    check_dependencies
    add_targets
    clean_build
    
    build_arm64
    build_x86_64
    create_universal_binary
    
    create_install_structure
    create_launchd_plist
    create_preinstall_script
    create_postinstall_script
    create_component_package
    create_distribution_xml
    create_installer_resources
    create_final_package
    create_uninstaller
    
    show_summary
    
    success "Build process completed successfully!"
}

# Run main function
main "$@"
