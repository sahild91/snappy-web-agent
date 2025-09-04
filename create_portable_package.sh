#!/bin/bash
# Create a portable Windows package since MSI creation failed in Wine

echo "Creating portable Windows package..."

# Create package directory
mkdir -p "snappy-web-agent-windows-portable"

# Copy executable
cp build/x64/snappy-web-agent.exe snappy-web-agent-windows-portable/

# Copy documentation
cp README.md snappy-web-agent-windows-portable/
cp LICENSE.rtf snappy-web-agent-windows-portable/ 2>/dev/null || echo "Note: LICENSE.rtf not found"

# Copy service manager
cp wix/service-manager.bat snappy-web-agent-windows-portable/

# Create installation guide
cat > snappy-web-agent-windows-portable/INSTALL.md << 'EOF'
# Snappy Web Agent - Portable Windows Installation

## Quick Start

1. **Extract** this folder to your desired location (e.g., `C:\SnappyWebAgent\`)
2. **Run as Administrator** - Right-click `install-service.bat` and select "Run as administrator"
3. **Start the service** using `start-service.bat`

## Files Included

- `snappy-web-agent.exe` - Main application
- `service-manager.bat` - Service management script
- `install-service.bat` - Quick installation script
- `start-service.bat` - Start service script
- `stop-service.bat` - Stop service script
- `uninstall-service.bat` - Uninstall service script
- `README.md` - Project documentation
- `LICENSE.rtf` - License information

## Manual Installation

### Install as Windows Service

```batch
# Install service (Run as Administrator)
service-manager.bat install

# Start service
service-manager.bat start

# Check service status
sc query SnappyWebAgent
```

### Uninstall Service

```batch
# Stop and uninstall service (Run as Administrator)
service-manager.bat stop
service-manager.bat uninstall
```

## Service Management

The service will:
- Automatically start on system boot
- Listen on ports 8436-8535 (finds first available)
- Log to Windows Event Viewer
- Automatically restart if it crashes

## Firewall

If you need to access from other computers:
1. Open Windows Firewall
2. Add inbound rule for ports 8436-8535 (TCP)

## Troubleshooting

**Service won't start:**
1. Run Command Prompt as Administrator
2. Navigate to the installation folder
3. Run: `snappy-web-agent.exe` directly to see error messages

**Port conflicts:**
- Check which ports are in use: `netstat -an | findstr :843`
- Stop other applications using those ports

**Permissions:**
- Ensure you're running as Administrator for service operations
- The executable needs access to USB/Serial ports

## Support

- GitHub: https://github.com/gouthamsk98/snappy-web-agent
- Issues: Report problems on GitHub Issues

EOF

# Create installation scripts
cat > snappy-web-agent-windows-portable/install-service.bat << 'EOF'
@echo off
echo Installing Snappy Web Agent Service...
echo.
echo This will install the service to run automatically on system startup.
echo.
pause

cd /d "%~dp0"
service-manager.bat install
if %errorlevel% equ 0 (
    echo.
    echo Service installed successfully!
    echo Starting service...
    service-manager.bat start
    echo.
    echo Installation complete. The service is now running.
) else (
    echo.
    echo Installation failed. Please run as Administrator.
)
pause
EOF

cat > snappy-web-agent-windows-portable/start-service.bat << 'EOF'
@echo off
echo Starting Snappy Web Agent Service...
cd /d "%~dp0"
service-manager.bat start
echo.
sc query SnappyWebAgent
pause
EOF

cat > snappy-web-agent-windows-portable/stop-service.bat << 'EOF'
@echo off
echo Stopping Snappy Web Agent Service...
cd /d "%~dp0"
service-manager.bat stop
echo.
sc query SnappyWebAgent
pause
EOF

cat > snappy-web-agent-windows-portable/uninstall-service.bat << 'EOF'
@echo off
echo Uninstalling Snappy Web Agent Service...
echo.
echo This will stop and remove the service.
echo.
pause

cd /d "%~dp0"
service-manager.bat stop
service-manager.bat uninstall
if %errorlevel% equ 0 (
    echo.
    echo Service uninstalled successfully!
) else (
    echo.
    echo Uninstallation may have failed. Check Windows Services.
)
pause
EOF

# Create ZIP package
zip -r snappy-web-agent-windows-portable.zip snappy-web-agent-windows-portable/

echo "✓ Windows portable package created: snappy-web-agent-windows-portable.zip"
echo "✓ Package size: $(du -h snappy-web-agent-windows-portable.zip | cut -f1)"
echo ""
echo "Package contents:"
echo "- Windows executable (6.0 MB)"
echo "- Service management scripts"
echo "- Installation documentation"
echo "- Easy-to-use batch files for installation"
echo ""
echo "Users can extract and run 'install-service.bat' as Administrator to install."
