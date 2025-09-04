#!/bin/bash
# Simple NSIS build script for Snappy Web Agent

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_info "Building Snappy Web Agent Windows Installer with NSIS..."

# Check if NSIS is installed
if ! command -v makensis &> /dev/null; then
    log_error "NSIS not found. Installing..."
    sudo apt install -y nsis
fi

# Check if MinGW is installed
if ! command -v x86_64-w64-mingw32-gcc &> /dev/null; then
    log_warning "MinGW not found. Installing..."
    sudo apt install -y gcc-mingw-w64-x86-64
fi

# Add Rust Windows target
log_info "Adding Rust Windows target..."
rustup target add x86_64-pc-windows-gnu

# Build Windows executable
log_info "Building Windows executable..."
cargo build --release --target x86_64-pc-windows-gnu

# Check if build was successful
if [ ! -f "target/x86_64-pc-windows-gnu/release/snappy-web-agent.exe" ]; then
    log_error "Windows executable not found!"
    exit 1
fi

# Create build directory structure for NSIS
log_info "Preparing build structure..."
mkdir -p build/x64
cp target/x86_64-pc-windows-gnu/release/snappy-web-agent.exe build/x64/

# Create wix directory with service manager (NSIS expects this structure)
mkdir -p wix
cat > wix/service-manager.bat << 'EOF'
@echo off
REM Snappy Web Agent Service Manager

set SERVICE_NAME=SnappyWebAgent
set APP_NAME=snappy-web-agent
set INSTALL_DIR=%~dp0

if "%1"=="install" goto :install
if "%1"=="uninstall" goto :uninstall
if "%1"=="start" goto :start
if "%1"=="stop" goto :stop
if "%1"=="restart" goto :restart

echo Usage: %0 [install^|uninstall^|start^|stop^|restart]
echo.
echo Available commands:
echo   install   - Install the service
echo   uninstall - Remove the service
echo   start     - Start the service
echo   stop      - Stop the service
echo   restart   - Restart the service
goto :eof

:install
echo Installing %SERVICE_NAME% service...
sc create "%SERVICE_NAME%" binPath= "\"%INSTALL_DIR%%APP_NAME%.exe\" --service" DisplayName= "Snappy Web Agent Service" start= auto type= own error= normal
if %errorlevel% equ 0 (
    echo Service installed successfully
    echo Configuring service for background operation...
    sc config "%SERVICE_NAME%" start= auto
    sc failure "%SERVICE_NAME%" reset= 86400 actions= restart/5000/restart/10000/restart/30000
    sc description "%SERVICE_NAME%" "Snappy Web Agent Service - Handles communication between web applications and hardware devices"
    echo Starting service...
    sc start "%SERVICE_NAME%"
    if %errorlevel% equ 0 (
        echo Service started successfully and will run in background
    ) else (
        echo Service installed but failed to start (will start automatically on next boot)
    )
) else (
    echo Failed to install service
)
goto :eof

:uninstall
echo Stopping %SERVICE_NAME% service...
sc stop "%SERVICE_NAME%" >nul 2>&1
timeout /t 2 /nobreak >nul 2>&1
echo Uninstalling %SERVICE_NAME% service...
sc delete "%SERVICE_NAME%"
if %errorlevel% equ 0 (
    echo Service uninstalled successfully
) else (
    echo Failed to uninstall service
)
goto :eof

:start
echo Starting %SERVICE_NAME% service...
sc start "%SERVICE_NAME%"
goto :eof

:stop
echo Stopping %SERVICE_NAME% service...
sc stop "%SERVICE_NAME%"
goto :eof

:restart
echo Restarting %SERVICE_NAME% service...
sc stop "%SERVICE_NAME%" >nul 2>&1
timeout /t 3 /nobreak >nul 2>&1
sc start "%SERVICE_NAME%"
goto :eof
EOF

# Create license file if it doesn't exist
if [ ! -f LICENSE.rtf ]; then
    log_warning "Creating dummy LICENSE.rtf (replace with real license)"
    cat > LICENSE.rtf << 'EOF'
{\rtf1\ansi\deff0 {\fonttbl {\f0 Times New Roman;}}
\f0\fs24
Snappy Web Agent License

Copyright (c) YuduRobotics

Permission is hereby granted to use this software.
Replace this with your actual license terms.
}
EOF
fi

# Build NSIS installer
log_info "Building NSIS installer..."
makensis installer.nsi

if [ $? -eq 0 ]; then
    installer_size=$(du -h snappy-web-agent-1.0.0-setup.exe | cut -f1)
    log_success "NSIS installer created successfully!"
    log_success "Installer: snappy-web-agent-1.0.0-setup.exe (${installer_size})"
    echo ""
    echo "=========================="
    echo "Build Summary:"
    echo "=========================="
    echo "✓ Windows executable: $(du -h target/x86_64-pc-windows-gnu/release/snappy-web-agent.exe | cut -f1)"
    echo "✓ NSIS installer: ${installer_size}"
    echo "✓ Cross-compiled on Linux using MinGW"
    echo "✓ Professional installer with service management"
    echo "✓ Automatic service installation and startup"
    echo ""
    echo "The installer can be run on any Windows 7+ (64-bit) system"
    echo "and will automatically install and start the service."
else
    log_error "NSIS installer build failed"
    exit 1
fi
