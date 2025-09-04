#!/bin/bash
# Snappy Web Agent - Wine Build Script
# Sets up Wine environment and builds Windows installer

set -e

# Configuration
WINE_PREFIX="$HOME/.wine-snappy"
WINE_ARCH="win64"
POWERSHELL_VERSION="7.4.4"
WIX_VERSION="3.11"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Wine is installed
check_wine() {
    if ! command -v wine &> /dev/null; then
        log_error "Wine is not installed. Please install Wine first:"
        echo "  Ubuntu/Debian: sudo apt install wine64"
        echo "  Fedora: sudo dnf install wine"
        echo "  Arch: sudo pacman -S wine"
        exit 1
    fi
    log_success "Wine found: $(wine --version)"
}

# Check if Rust is installed with Windows target
check_rust() {
    if ! command -v cargo &> /dev/null; then
        log_error "Rust is not installed. Please install from https://rustup.rs/"
        exit 1
    fi
    
    # Add Windows GNU target (no MSVC needed with Wine)
    log_info "Adding Rust Windows GNU target..."
    rustup target add x86_64-pc-windows-gnu
    log_success "Rust Windows target added"
}

# Create Wine prefix
setup_wine_prefix() {
    log_info "Setting up Wine prefix at $WINE_PREFIX..."
    
    if [ -d "$WINE_PREFIX" ]; then
        log_warning "Wine prefix already exists. Use --clean to recreate it."
    else
        WINEPREFIX="$WINE_PREFIX" WINEARCH="$WINE_ARCH" wineboot --init
        log_success "Wine prefix created"
    fi
}

# Install PowerShell in Wine
install_powershell() {
    log_info "Installing PowerShell $POWERSHELL_VERSION in Wine..."
    
    local ps_msi="PowerShell-${POWERSHELL_VERSION}-win-x64.msi"
    local ps_url="https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/${ps_msi}"
    
    if [ ! -f "/tmp/$ps_msi" ]; then
        log_info "Downloading PowerShell installer..."
        wget -O "/tmp/$ps_msi" "$ps_url"
    fi
    
    log_info "Installing PowerShell..."
    WINEPREFIX="$WINE_PREFIX" wine msiexec /i "/tmp/$ps_msi" /qn
    log_success "PowerShell installed"
}

# Install WiX Toolset in Wine
install_wix() {
    log_info "Installing WiX Toolset $WIX_VERSION in Wine..."
    
    local wix_zip="wix311-binaries.zip"
    local wix_url="https://github.com/wixtoolset/wix3/releases/download/wix3112rtm/$wix_zip"
    
    if [ ! -f "/tmp/$wix_zip" ]; then
        log_info "Downloading WiX binaries..."
        wget -O "/tmp/$wix_zip" "$wix_url"
    fi
    
    log_info "Extracting WiX to Wine prefix..."
    mkdir -p "$WINE_PREFIX/drive_c/wix"
    unzip -o "/tmp/$wix_zip" -d "$WINE_PREFIX/drive_c/wix/"
    log_success "WiX installed"
}

# Modify build script for Wine/GNU target
modify_build_script() {
    log_info "Creating Wine-compatible build script..."
    
    # Create a modified version of the PowerShell script for Wine
    cat > "build_wine.ps1" << 'EOF'
# Wine-compatible version of build_windows.ps1
param(
    [switch]$Help,
    [switch]$Clean,
    [switch]$SkipBuild
)

# Configuration
$APP_NAME = "snappy-web-agent"
$APP_VERSION = "1.0.0"
$COMPANY_NAME = "YuduRobotics"
$BUILD_DIR = "build"
$DIST_DIR = "dist"
$WIX_DIR = "wix"
$SERVICE_NAME = "SnappyWebAgent"
$SERVICE_DISPLAY_NAME = "Snappy Web Agent Service"

# Add WiX to PATH
$env:PATH += ";C:\wix"

# Color functions
function Write-Success { param($Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Blue }
function Write-Warning { param($Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "✗ $Message" -ForegroundColor Red }

# Check WiX dependencies only (Rust build happens outside Wine)
function Test-Dependencies {
    Write-Info "Checking WiX dependencies..."
    
    $errors = @()
    
    if (!(Get-Command candle.exe -ErrorAction SilentlyContinue)) {
        $errors += "WiX candle.exe not found. Ensure WiX is in PATH."
    }
    
    if (!(Get-Command light.exe -ErrorAction SilentlyContinue)) {
        $errors += "WiX light.exe not found. Ensure WiX is in PATH."
    }
    
    if ($errors.Count -gt 0) {
        foreach ($error in $errors) {
            Write-Error $error
        }
        exit 1
    }
    
    Write-Success "WiX tools found"
}

# Clean function (Wine-compatible paths)
function Invoke-Clean {
    Write-Info "Cleaning previous builds..."
    
    $itemsToRemove = @(
        $BUILD_DIR,
        $DIST_DIR,
        $WIX_DIR,
        "*.msi",
        "uninstall_$APP_NAME.bat",
        "Windows_Installation_Guide.md"
    )
    
    foreach ($item in $itemsToRemove) {
        if (Test-Path $item) {
            Remove-Item $item -Recurse -Force
        }
    }
    
    Write-Success "Clean completed"
}

# Rest of the functions from original script...
# (Copy the relevant functions from build_windows.ps1)

EOF

    # Append the rest of the functions from the original script
    # Extract functions from original script (excluding Rust build parts)
    sed -n '/^# Create directory structure/,/^# Main execution/p' build_windows.ps1 | \
    sed 's/target\\x86_64-pc-windows-msvc\\release/target\/x86_64-pc-windows-gnu\/release/g' | \
    sed '/Add-RustTargets\|Build-Target/d' >> build_wine.ps1
    
    # Add Wine-specific main execution
    cat >> "build_wine.ps1" << 'EOF'

# Main execution (Wine version)
try {
    Test-Dependencies
    
    if ($Clean) {
        Invoke-Clean
        Write-Success "Clean completed successfully!"
        exit 0
    }
    
    Invoke-Clean
    
    # Skip Rust build - done outside Wine
    Write-Info "Skipping Rust build (done outside Wine)"
    
    # Check if binary exists
    $expectedBinary = "target/x86_64-pc-windows-gnu/release/$APP_NAME.exe"
    if (!(Test-Path $expectedBinary)) {
        Write-Error "Windows binary not found at $expectedBinary"
        Write-Error "Please run: cargo build --release --target x86_64-pc-windows-gnu"
        exit 1
    }
    
    New-BuildStructure
    New-DistStructure
    New-ServiceManager
    New-WixInstaller
    Build-MsiInstaller
    New-Uninstaller
    New-InstallationGuide
    
    Show-BuildSummary
    Write-Success "Wine build process completed successfully!"
}
catch {
    Write-Error "Build failed: $($_.Exception.Message)"
    exit 1
}
EOF

    log_success "Wine-compatible build script created"
}

# Build Rust binary with GNU target
build_rust_binary() {
    log_info "Building Rust binary for Windows..."
    
    # First try with musl target (static linking, no MinGW needed)
    log_info "Trying musl target (static linking)..."
    if rustup target add x86_64-pc-windows-msvc && cargo build --release --target x86_64-pc-windows-msvc; then
        log_success "Built with MSVC target (no MinGW needed)"
        return 0
    fi
    
    # Fallback to GNU target with MinGW
    log_info "Trying GNU target with MinGW..."
    
    # Install mingw-w64 if not present
    if ! command -v x86_64-w64-mingw32-gcc &> /dev/null; then
        log_warning "MinGW-w64 not found. Trying to install..."
        
        # Try manual installation from Ubuntu packages
        log_info "Attempting manual MinGW installation..."
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/m/mingw-w64/gcc-mingw-w64-x86-64_10.3.0-9ubuntu1+22build3_amd64.deb -O /tmp/mingw.deb
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/m/mingw-w64/mingw-w64-common_9.0.0-1_all.deb -O /tmp/mingw-common.deb
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/m/mingw-w64/mingw-w64-x86-64-dev_9.0.0-1_all.deb -O /tmp/mingw-dev.deb
        
        if sudo dpkg -i /tmp/mingw*.deb 2>/dev/null; then
            log_success "MinGW installed manually"
        else
            log_warning "Manual MinGW installation failed, trying alternative approach..."
            # Use a Docker container for cross-compilation
            if command -v docker &> /dev/null; then
                log_info "Using Docker for cross-compilation..."
                docker run --rm -v "$(pwd)":/workspace -w /workspace \
                    rust:latest bash -c "
                    rustup target add x86_64-pc-windows-gnu && \
                    apt-get update && apt-get install -y gcc-mingw-w64-x86-64 && \
                    cargo build --release --target x86_64-pc-windows-gnu
                    "
                log_success "Cross-compilation completed with Docker"
                return 0
            else
                log_error "Neither MinGW nor Docker available for cross-compilation"
                log_error "Please install MinGW manually or use native Windows build"
                exit 1
            fi
        fi
    fi
    
    cargo build --release --target x86_64-pc-windows-gnu
    log_success "Rust binary built successfully"
}

# Build NSIS installer
build_nsis_installer() {
    log_info "Building NSIS installer..."
    
    # Check if NSIS is available
    if ! command -v makensis &> /dev/null; then
        log_error "NSIS not found. Installing..."
        sudo apt install -y nsis
    fi
    
    # Ensure we have a license file
    if [ ! -f LICENSE.rtf ]; then
        log_warning "LICENSE.rtf not found, creating dummy license"
        echo "License file not provided" > LICENSE.rtf
    fi
    
    # Build the installer
    makensis installer.nsi
    
    if [ $? -eq 0 ]; then
        log_success "NSIS installer created successfully"
        if [ -f "snappy-web-agent-1.0.0-setup.exe" ]; then
            local size=$(du -h "snappy-web-agent-1.0.0-setup.exe" | cut -f1)
            log_success "Installer size: $size"
        fi
    else
        log_error "NSIS installer build failed"
        exit 1
    fi
}

# Clean Wine prefix
clean_wine() {
    log_info "Cleaning Wine prefix..."
    if [ -d "$WINE_PREFIX" ]; then
        rm -rf "$WINE_PREFIX"
        log_success "Wine prefix cleaned"
    fi
}

# Main function
main() {
    case "${1:-build}" in
        "setup")
            check_wine
            setup_wine_prefix
            install_powershell
            install_wix
            log_success "Wine environment setup complete"
            ;;
        "build")
            check_wine
            check_rust
            build_rust_binary
            build_nsis_installer
            log_success "Build completed! NSIS installer created."
            ;;
        "clean")
            clean_wine
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  setup    Setup Wine environment with PowerShell and WiX"
            echo "  build    Build the Windows installer (default)"
            echo "  clean    Clean Wine prefix"
            echo "  help     Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 setup    # First time setup"
            echo "  $0 build    # Build installer"
            echo "  $0 clean    # Clean and start over"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
