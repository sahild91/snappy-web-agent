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

# Create directory structure
function New-BuildStructure {
    Write-Info "Creating build directory structure..."
    
    New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path "$BUILD_DIR\x64" -Force | Out-Null
    
    # Check if binaries exist before copying
    $x64Binary = "target/x86_64-pc-windows-gnu/release\$APP_NAME.exe"
    $x64BinaryGnu = "target\x86_64-pc-windows-gnu\release\$APP_NAME.exe"
    
    Write-Info "Looking for x64 binary..."
    if (Test-Path $x64Binary) {
        Copy-Item $x64Binary "$BUILD_DIR\x64\"
        Write-Success "Copied x64 binary (MSVC)"
    } elseif (Test-Path $x64BinaryGnu) {
        Copy-Item $x64BinaryGnu "$BUILD_DIR\x64\"
        Write-Success "Copied x64 binary (GNU)"
    } else {
        Write-Error "x64 binary not found at either:"
        Write-Error "  MSVC: $x64Binary"
        Write-Error "  GNU:  $x64BinaryGnu"
        Write-Info "Contents of target directories:"
        if (Test-Path "target/x86_64-pc-windows-gnu/release\") {
            Write-Info "MSVC target contents:"
            Get-ChildItem "target/x86_64-pc-windows-gnu/release\" | Write-Host
        }
        if (Test-Path "target\x86_64-pc-windows-gnu\release\") {
            Write-Info "GNU target contents:"
            Get-ChildItem "target\x86_64-pc-windows-gnu\release\" | Write-Host
        }
    }
    
    Write-Success "Build directory structure created"
}

function New-DistStructure {
    Write-Info "Creating installation directory structure..."
    
    New-Item -ItemType Directory -Path $DIST_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path "$DIST_DIR\x64" -Force | Out-Null
    New-Item -ItemType Directory -Path "$DIST_DIR\docs" -Force | Out-Null
    
    # Copy binaries with error checking
    $x64Source = "$BUILD_DIR\x64\$APP_NAME.exe"
    
    if (Test-Path $x64Source) {
        Copy-Item $x64Source "$DIST_DIR\x64\"
        Write-Success "Copied x64 binary to dist"
    } else {
        Write-Error "x64 binary not found in build directory: $x64Source"
    }
    
    # Copy README
    if (Test-Path "README.md") {
        Copy-Item "README.md" "$DIST_DIR\docs\"
        Write-Success "Copied README.md to dist"
    } else {
        Write-Error "README.md not found in root directory"
    }
    
    Write-Success "Installation structure created"
}

# Create service manager
function New-ServiceManager {
    Write-Info "Creating service wrapper..."
    
    New-Item -ItemType Directory -Path $WIX_DIR -Force | Out-Null
    
    # Copy license file to WiX directory
    if (Test-Path "LICENSE.rtf") {
        Copy-Item "LICENSE.rtf" "$WIX_DIR\"
        Write-Success "Copied license file to WiX directory"
    } else {
        Write-Warning "LICENSE.rtf not found, installer will not have license agreement"
    }
    
    $serviceScript = @"
@echo off
REM Snappy Web Agent Service Wrapper
REM This script manages the Snappy Web Agent as a Windows Service

set SERVICE_NAME=$SERVICE_NAME
set APP_NAME=$APP_NAME
set INSTALL_DIR=%PROGRAMFILES%\$COMPANY_NAME\Snappy Web Agent

if "%1"=="install" goto :install
if "%1"=="uninstall" goto :uninstall
if "%1"=="start" goto :start
if "%1"=="stop" goto :stop
if "%1"=="restart" goto :restart

echo Usage: %0 [install^|uninstall^|start^|stop^|restart]
goto :eof

:install
echo Installing %SERVICE_NAME% service...
sc create "%SERVICE_NAME%" binPath= "\"%INSTALL_DIR%\%APP_NAME%.exe\"" DisplayName= "$SERVICE_DISPLAY_NAME" start= auto
if %errorlevel% equ 0 (
    echo Service installed successfully
    echo Starting service...
    sc start "%SERVICE_NAME%"
) else (
    echo Failed to install service
)
goto :eof

:uninstall
echo Stopping %SERVICE_NAME% service...
sc stop "%SERVICE_NAME%"
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
sc stop "%SERVICE_NAME%"
timeout /t 3 /nobreak >nul
sc start "%SERVICE_NAME%"
goto :eof
"@
    
    $serviceScript | Out-File -FilePath "$WIX_DIR\service-manager.bat" -Encoding ASCII
    Write-Success "Service wrapper created"
}

# Create WiX installer
function New-WixInstaller {
    Write-Info "Creating WiX installer source..."
    # Determine source file paths (prefer build directory outputs)
    $x64Src = "build/x64/$APP_NAME.exe"
    $readmeSrc = "README.md"
    $licenseSrc = "LICENSE.rtf"
    $serviceManagerSrc = "$WIX_DIR/service-manager.bat"

    if (!(Test-Path $x64Src)) { Write-Warning "Expected x64 binary missing at $x64Src" }
    if (!(Test-Path $serviceManagerSrc)) { Write-Warning "Service manager script missing at $serviceManagerSrc" }
    if (!(Test-Path $readmeSrc)) { Write-Warning "README missing at $readmeSrc" }
    if (!(Test-Path $licenseSrc)) { Write-Warning "LICENSE.rtf missing at $licenseSrc" }

    # Component XML for main executable (only if present)
    if (Test-Path $x64Src) {
        # Executable component also carries service installation so its file is the KeyPath (avoids ICE18)
        $exeComponentsXml = @"
    <Component Id="MainExecutableX64" Guid="9F6F8E9A-4E5D-4A7E-9E3D-9A6C2B7D1F10" Directory="INSTALLFOLDER" Win64="yes">
      <File Id="MainExeX64" Source="..\build\x64\$APP_NAME.exe" KeyPath="yes" />
      <ServiceInstall Id="SnappyWebAgentService"
                      Name="$SERVICE_NAME"
                      DisplayName="$SERVICE_DISPLAY_NAME"
                      Description="Snappy Web Agent - Serial device data collection and streaming service"
                      Type="ownProcess"
                      Start="auto"
                      Account="LocalSystem"
                      ErrorControl="normal"
                      Interactive="no" />
      <ServiceControl Id="StartService" Name="$SERVICE_NAME" Start="install" Stop="both" Remove="uninstall" Wait="yes" />
    </Component>
"@
        $mainComponentRef = '<ComponentRef Id="MainExecutableX64" />'
    } else {
        $exeComponentsXml = ""
        $mainComponentRef = ""
    }

    $wixSource = @"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="Snappy Web Agent" Language="1033" Version="$APP_VERSION" Manufacturer="$COMPANY_NAME" UpgradeCode="12345678-1234-1234-1234-123456789012">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" InstallPrivileges="elevated" 
             Description="Snappy Web Agent - Serial device communication service"
             Comments="Installs Snappy Web Agent service for serial device data collection"
             Keywords="Serial,USB,Data Collection,Service"
             Platform="x64" />

    <!-- Require Windows 7 or later -->
    <Condition Message="This application requires Windows 7 or later.">
      <![CDATA[Installed OR (VersionNT >= 601)]]>
    </Condition>

    <!-- Require Administrator privileges -->
    <Condition Message="You must be an administrator to install this application.">
      <![CDATA[Installed OR Privileged]]>
    </Condition>

    <MajorUpgrade DowngradeErrorMessage="A newer version of [ProductName] is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <!-- Custom Properties -->
    <Property Id="ARPPRODUCTICON" Value="icon.ico" />
    <Property Id="ARPHELPLINK" Value="https://github.com/gouthamsk98/snappy-web-agent" />
    <Property Id="ARPURLINFOABOUT" Value="https://github.com/gouthamsk98/snappy-web-agent" />
    <Property Id="ARPNOREPAIR" Value="1" />
    <!-- Removed ARPNOMODIFY to avoid duplicate symbol with WixUI_InstallDir -->
    
    <!-- License file property -->
    <Property Id="WixUILicenseRtf" Value="LICENSE.rtf" />

    <!-- Directory Structure -->
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="CompanyFolder" Name="$COMPANY_NAME">
          <Directory Id="INSTALLFOLDER" Name="Snappy Web Agent">
            <Directory Id="DocsFolder" Name="docs" />
          </Directory>
        </Directory>
      </Directory>
      <Directory Id="CommonAppDataFolder">
        <Directory Id="AppDataCompanyFolder" Name="$COMPANY_NAME">
          <Directory Id="AppDataAppFolder" Name="Snappy Web Agent">
            <Directory Id="LogsFolder" Name="logs" />
            <Directory Id="ConfigFolder" Name="config" />
          </Directory>
        </Directory>
      </Directory>
      <Directory Id="ProgramMenuFolder">
        <Directory Id="ApplicationProgramsFolder" Name="Snappy Web Agent" />
      </Directory>
    </Directory>

        <!-- Components -->
        <ComponentGroup Id="ProductComponents">
            <!-- Executable Components -->
            $exeComponentsXml

            <!-- Service Manager Script -->
            <Component Id="ServiceManager" Guid="A2D31B7C-7B84-4F0A-A6E1-2D45F9B6C3A1" Directory="INSTALLFOLDER" Win64="yes">
                <File Id="ServiceManagerBat" Source="service-manager.bat" KeyPath="yes" />
            </Component>
        </ComponentGroup>

        <!-- Documentation Components in docs folder -->
        <ComponentGroup Id="DocumentationComponents">
            <!-- Documentation -->
            <Component Id="Documentation" Guid="C4E8A9D2-3F61-42D5-9F7B-1B2C3D4E5F60" Directory="DocsFolder" Win64="yes">
                <File Id="ReadmeFile" Source="..\README.md" KeyPath="yes" />
            </Component>

            <!-- License File -->
            <Component Id="LicenseFile" Guid="D5F7A8B9-1C2E-4F3A-8B6D-9E7A5C2F1B8D" Directory="DocsFolder" Win64="yes">
                <File Id="LicenseRtf" Source="..\LICENSE.rtf" KeyPath="yes" />
            </Component>
        </ComponentGroup>

    <!-- Start Menu Shortcuts -->
    <DirectoryRef Id="ApplicationProgramsFolder">
      <Component Id="ApplicationShortcut" Guid="*">
        <Shortcut Id="ServiceManagerShortcut"
                  Name="Snappy Web Agent Service Manager"
                  Description="Manage Snappy Web Agent Service"
                  Target="[INSTALLFOLDER]service-manager.bat"
                  WorkingDirectory="INSTALLFOLDER" />
        <Shortcut Id="UninstallShortcut"
                  Name="Uninstall Snappy Web Agent"
                  Description="Uninstall Snappy Web Agent"
                  Target="[SystemFolder]msiexec.exe"
                  Arguments="/x [ProductCode]" />
        <Shortcut Id="ReadmeShortcut"
                  Name="README"
                  Description="Read the documentation"
                  Target="[INSTALLFOLDER]docs\README.md" />
        <RemoveFolder Id="ApplicationProgramsFolder" On="uninstall" />
        <RegistryValue Root="HKCU" Key="Software\$COMPANY_NAME\Snappy Web Agent" Name="installed" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </DirectoryRef>

    <!-- Logs Directory -->
    <Component Id="LogsDirectory" Guid="E8F9A0B1-C2D3-4E5F-9012-3456789ABCDE" Directory="LogsFolder">
      <CreateFolder />
      <RemoveFolder Id="LogsFolder" On="uninstall" />
      <RegistryValue Root="HKLM" Key="Software\$COMPANY_NAME\Snappy Web Agent" Name="LogsPath" Type="string" Value="[LogsFolder]" KeyPath="yes" />
    </Component>

    <!-- Config Directory -->
    <Component Id="ConfigDirectory" Guid="F1A2B3C4-D5E6-F7A8-B9C0-D1E2F3A4B5C6" Directory="ConfigFolder">
      <CreateFolder />
      <RemoveFolder Id="ConfigFolder" On="uninstall" />
      <RegistryValue Root="HKLM" Key="Software\$COMPANY_NAME\Snappy Web Agent" Name="ConfigPath" Type="string" Value="[ConfigFolder]" KeyPath="yes" />
    </Component>

    <!-- Registry entries for version and install path -->
    <Component Id="RegistryEntries" Guid="A1B2C3D4-E5F6-A7B8-C9D0-E1F2A3B4C5D6" Directory="INSTALLFOLDER" Win64="yes">
      <RegistryValue Root="HKLM" Key="Software\$COMPANY_NAME\Snappy Web Agent" Name="Version" Type="string" Value="$APP_VERSION" KeyPath="yes" />
      <RegistryValue Root="HKLM" Key="Software\$COMPANY_NAME\Snappy Web Agent" Name="InstallPath" Type="string" Value="[INSTALLFOLDER]" />
      <RegistryValue Root="HKLM" Key="Software\$COMPANY_NAME\Snappy Web Agent" Name="ServiceName" Type="string" Value="$SERVICE_NAME" />
    </Component>

    <!-- Feature Definition -->
        <Feature Id="ProductFeature" Title="Snappy Web Agent" Level="1" Description="Core application and service components">
            <ComponentGroupRef Id="ProductComponents" />
            <ComponentGroupRef Id="DocumentationComponents" />
            <ComponentRef Id="ApplicationShortcut" />
            <ComponentRef Id="LogsDirectory" />
            <ComponentRef Id="ConfigDirectory" />
            <ComponentRef Id="RegistryEntries" />
            $mainComponentRef
        </Feature>

    <!-- Custom Actions -->
    <CustomAction Id="SetARPINSTALLLOCATION" Property="ARPINSTALLLOCATION" Value="[INSTALLFOLDER]" />
    
    <!-- Installation Sequence -->
    <InstallExecuteSequence>
      <Custom Action="SetARPINSTALLLOCATION" After="CostFinalize" />
    </InstallExecuteSequence>

    <!-- UI Configuration -->
    <Property Id="WIXUI_INSTALLDIR" Value="INSTALLFOLDER" />
    <UIRef Id="WixUI_InstallDir" />
    <UIRef Id="WixUI_ErrorProgressText" />

    <!-- Custom banner and dialog images (optional) -->
    <!-- 
    <WixVariable Id="WixUIBannerBmp" Value="banner.bmp" />
    <WixVariable Id="WixUIDialogBmp" Value="dialog.bmp" />
    -->

  </Product>
</Wix>
"@
    
    $wixSource | Out-File -FilePath "$WIX_DIR\$APP_NAME.wxs" -Encoding UTF8
    Write-Success "WiX source created"
}

function Build-MsiInstaller {
    Write-Info "Compiling MSI installer..."
    
    Push-Location $WIX_DIR
    
    try {
        & candle.exe -out "$APP_NAME.wixobj" "$APP_NAME.wxs"
        if ($LASTEXITCODE -ne 0) {
            throw "WiX compilation failed"
        }
        
        & light.exe -out "..\$APP_NAME-$APP_VERSION-setup.msi" "$APP_NAME.wixobj" -ext WixUIExtension
        if ($LASTEXITCODE -ne 0) {
            throw "WiX linking failed"
        }
        
        Write-Success "MSI installer created: $APP_NAME-$APP_VERSION-setup.msi"
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
    finally {
        Pop-Location
    }
}

# Create uninstaller
function New-Uninstaller {
    Write-Info "Creating uninstaller script..."
    
    $uninstallScript = @"
@echo off
REM Snappy Web Agent Uninstaller
REM This script provides multiple ways to uninstall Snappy Web Agent

setlocal enabledelayedexpansion

echo ============================================
echo Snappy Web Agent Uninstaller
echo ============================================
echo.

REM Check if running as administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: This script must be run as Administrator!
    echo Right-click this file and select "Run as administrator"
    pause
    exit /b 1
)

echo Please choose an uninstallation method:
echo.
echo 1. Automatic uninstall (recommended)
echo 2. Service-only removal
echo 3. Manual cleanup
echo 4. Cancel
echo.
set /p choice="Enter your choice (1-4): "

if "%choice%"=="1" goto :auto_uninstall
if "%choice%"=="2" goto :service_only
if "%choice%"=="3" goto :manual_cleanup
if "%choice%"=="4" goto :cancel
echo Invalid choice. Exiting.
goto :cancel

:auto_uninstall
echo.
echo Attempting automatic uninstall...
echo.

REM Try to find the product code from registry
echo Searching for installed product...
for /f "tokens=*" %%i in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "Snappy Web Agent" 2^>nul ^| findstr "HKEY"') do (
    set "uninstall_key=%%i"
    goto :found_key
)

:found_key
if not defined uninstall_key (
    echo Product not found in registry. Trying service removal...
    goto :service_only
)

echo Found installation. Attempting to uninstall...
REM Extract product code from registry key
for /f "tokens=3 delims=\" %%a in ("!uninstall_key!") do set "product_code=%%a"

REM Attempt MSI uninstall
echo Running: msiexec /x {!product_code!} /quiet /norestart
msiexec /x {!product_code!} /quiet /norestart

if %errorlevel% equ 0 (
    echo Uninstallation completed successfully.
) else (
    echo MSI uninstall failed. Trying service removal...
    goto :service_only
)
goto :cleanup_check

:service_only
echo.
echo Removing service and cleaning up manually...
echo.

REM Stop and remove service
echo Stopping service...
sc stop "$SERVICE_NAME" 2>nul
timeout /t 3 /nobreak >nul

echo Removing service...
sc delete "$SERVICE_NAME" 2>nul

if %errorlevel% equ 0 (
    echo Service removed successfully.
) else (
    echo Service removal failed or service was not installed.
)

goto :manual_cleanup

:manual_cleanup
echo.
echo Performing manual cleanup...
echo.

REM Remove installation directory
set "install_dir=%PROGRAMFILES%\$COMPANY_NAME\Snappy Web Agent"
if exist "!install_dir!" (
    echo Removing installation directory...
    rmdir /s /q "!install_dir!" 2>nul
    if exist "!install_dir!" (
        echo Warning: Could not remove installation directory: !install_dir!
    ) else (
        echo Installation directory removed.
    )
)

REM Remove program data
set "data_dir=%PROGRAMDATA%\$COMPANY_NAME\Snappy Web Agent"
if exist "!data_dir!" (
    echo Removing application data...
    rmdir /s /q "!data_dir!" 2>nul
    if exist "!data_dir!" (
        echo Warning: Could not remove data directory: !data_dir!
    ) else (
        echo Application data removed.
    )
)

REM Remove Start Menu shortcuts
set "start_menu=%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Snappy Web Agent"
if exist "!start_menu!" (
    echo Removing Start Menu shortcuts...
    rmdir /s /q "!start_menu!" 2>nul
)

REM Remove registry entries
echo Removing registry entries...
reg delete "HKLM\SOFTWARE\$COMPANY_NAME\Snappy Web Agent" /f 2>nul
reg delete "HKCU\SOFTWARE\$COMPANY_NAME\Snappy Web Agent" /f 2>nul

goto :cleanup_check

:cleanup_check
echo.
echo Checking for remaining components...

REM Check if service still exists
sc query "$SERVICE_NAME" >nul 2>&1
if %errorlevel% equ 0 (
    echo Warning: Service "$SERVICE_NAME" still exists.
) else (
    echo Service removal confirmed.
)

REM Check if installation directory still exists
if exist "%PROGRAMFILES%\$COMPANY_NAME\Snappy Web Agent" (
    echo Warning: Installation directory still exists.
) else (
    echo Installation directory removal confirmed.
)

echo.
echo ============================================
echo Uninstallation process completed.
echo.
echo If you encounter any issues, please:
echo 1. Restart your computer
echo 2. Manually delete remaining files
echo 3. Check Windows Services for any remaining entries
echo ============================================
pause
goto :end

:cancel
echo Operation cancelled.
pause

:end
endlocal
"@
    
    $uninstallScript | Out-File -FilePath "uninstall_$APP_NAME.bat" -Encoding ASCII
    Write-Success "Enhanced uninstaller created: uninstall_$APP_NAME.bat"
}

# Create installation guide
function New-InstallationGuide {
    Write-Info "Creating installation guide..."
    
    $guide = @"
# Snappy Web Agent - Windows Installation Guide

## System Requirements
- Windows 7/8/10/11 (64-bit)
- Administrator privileges for installation and service management
- Available port starting from 8436
- .NET Framework 4.0 or later (usually pre-installed)

## Installation

### Option 1: MSI Installer (Recommended)
1. **Right-click** on ``$APP_NAME-$APP_VERSION-setup.msi`` and select **"Run as administrator"**
2. Follow the installation wizard:
   - Accept the license agreement
   - Choose installation directory (default: C:\Program Files\$COMPANY_NAME\Snappy Web Agent)
   - Click Install
3. The service will be automatically installed and started
4. Installation creates Start Menu shortcuts for easy management

**Important:** The installer requires administrator privileges. If you get an "insufficient privileges" error:
- Right-click the MSI file and select "Run as administrator"
- Or open Command Prompt as administrator and run: ``msiexec /i "$APP_NAME-$APP_VERSION-setup.msi"``

### Option 2: Manual Installation
1. Extract files to desired location
2. Open Command Prompt **as Administrator**
3. Navigate to the installation directory
4. Run ``service-manager.bat install``
5. Run ``service-manager.bat start`` to start the service

## Privilege Requirements

This application **requires administrator privileges** because it:
- Installs and manages a Windows Service
- Writes to Program Files directory
- Creates registry entries
- Accesses system-level USB/Serial ports

## Service Management

The Snappy Web Agent runs as a Windows Service. You can manage it using:

### Start Menu Shortcuts (After Installation)
- **Snappy Web Agent Service Manager**: Quick access to service controls
- **Uninstall Snappy Web Agent**: Easy uninstallation
- **README**: Documentation

### Service Manager Script
````batch
# Install service (requires admin)
service-manager.bat install

# Start service
service-manager.bat start

# Stop service
service-manager.bat stop

# Restart service
service-manager.bat restart

# Uninstall service (requires admin)
service-manager.bat uninstall
````

### Windows Services Manager
1. Press ``Win + R``, type ``services.msc``, press Enter
2. Find "$SERVICE_DISPLAY_NAME" in the list
3. Right-click to Start, Stop, or configure the service

### Command Line (Run as Administrator)
````batch
# Start service
sc start "$SERVICE_NAME"

# Stop service
sc stop "$SERVICE_NAME"

# Check service status
sc query "$SERVICE_NAME"

# Query service configuration
sc qc "$SERVICE_NAME"
````

## Configuration

The service will automatically:
- Find an available port starting from 8436
- Start on system boot (Automatic startup)
- Restart automatically if it crashes
- Log to Windows Event Log
- Create configuration and log directories

### Installation Directories
- **Program Files**: ``C:\Program Files\$COMPANY_NAME\Snappy Web Agent\``
- **Logs**: ``C:\ProgramData\$COMPANY_NAME\Snappy Web Agent\logs\``
- **Config**: ``C:\ProgramData\$COMPANY_NAME\Snappy Web Agent\config\``

## Logs and Monitoring

Service logs can be found in:
- **Windows Event Viewer**: Windows Logs > Application (Source: $SERVICE_NAME)
- **Log Files**: ``%PROGRAMDATA%\$COMPANY_NAME\Snappy Web Agent\logs\``

To view logs:
1. Press ``Win + R``, type ``eventvwr``, press Enter
2. Navigate to Windows Logs > Application
3. Filter by Source: "$SERVICE_NAME"

## Firewall Configuration

If you need to access the service from other computers:
1. Open Windows Firewall
2. Add inbound rule for ports 8436-8535 (TCP)
3. Or add exception for ``$APP_NAME.exe``

## Uninstallation

### Option 1: Control Panel (Recommended)
1. Go to Control Panel > Programs and Features
2. Find "Snappy Web Agent" and click Uninstall
3. Follow the uninstallation wizard

### Option 2: MSI Command Line
````batch
# Run as Administrator
msiexec /x "$APP_NAME-$APP_VERSION-setup.msi"
````

### Option 3: Start Menu
Use the "Uninstall Snappy Web Agent" shortcut from the Start Menu

## Troubleshooting

### Installation Issues

**"Insufficient privileges" error:**
- Right-click the installer and select "Run as administrator"
- Ensure you're logged in as an administrator
- Disable UAC temporarily if needed

**"Another version is already installed":**
- Uninstall the existing version first
- Or use the upgrade option in the installer

### Service Issues

**Service won't start:**
1. Check Windows Event Log for error details
2. Ensure no other application is using ports 8436-8535
3. Run ``service-manager.bat start`` as Administrator
4. Check if Windows Service is set to "Automatic" startup

**Port conflicts:**
The agent automatically finds available ports. If all ports in range are busy:
1. Stop other applications using those ports
2. Restart the service
3. Check netstat: ``netstat -an | findstr :843``

**Permission issues:**
1. Ensure the service is running as "Local System"
2. Check Windows Services Manager (``services.msc``)
3. Right-click "$SERVICE_DISPLAY_NAME" > Properties > Log On tab

### USB Device Access

**Device not detected:**
1. Ensure USB device drivers are installed
2. Check Device Manager for USB devices
3. Verify device VID/PID (0xb1b0/0x5508)
4. Try different USB ports
5. Restart the service after connecting device

## Support and Updates

- **GitHub Repository**: https://github.com/gouthamsk98/snappy-web-agent
- **Issues**: Report bugs and feature requests on GitHub
- **Documentation**: Latest README and documentation on GitHub

## Security Notes

- The service runs as Local System for hardware access
- No network data is transmitted outside your local system
- All communication is local (localhost) only
- USB device access is read-only for data collection

## Performance

- **Memory Usage**: Typically < 50MB
- **CPU Usage**: Minimal when idle, <5% during data collection
- **Network**: Local ports only (8436-8535 range)
- **Storage**: Logs rotate automatically, minimal disk usage
"@
    
    $guide | Out-File -FilePath "Windows_Installation_Guide.md" -Encoding UTF8
    Write-Success "Installation guide created: Windows_Installation_Guide.md"
}

# Show build summary
function Show-BuildSummary {
    Write-Info "Build Summary"
    Write-Host "==============================================" -ForegroundColor Blue
    Write-Success "x64 binary: $BUILD_DIR\x64\$APP_NAME.exe"
    Write-Success "MSI installer: $APP_NAME-$APP_VERSION-setup.msi"
    Write-Success "Enhanced uninstaller: uninstall_$APP_NAME.bat"
    Write-Success "Service manager: $WIX_DIR\service-manager.bat"
    Write-Success "License agreement: LICENSE.rtf"
    Write-Success "Installation guide: Windows_Installation_Guide.md"
    Write-Host ""
    
    Write-Host "Binary sizes:" -ForegroundColor Cyan
    if (Test-Path "$BUILD_DIR\x64\$APP_NAME.exe") {
        $x64Size = (Get-Item "$BUILD_DIR\x64\$APP_NAME.exe").Length
        Write-Host "  x64: $([math]::Round($x64Size/1MB, 2)) MB" -ForegroundColor White
    }
    
    Write-Host ""
    if (Test-Path "$APP_NAME-$APP_VERSION-setup.msi") {
        $msiSize = (Get-Item "$APP_NAME-$APP_VERSION-setup.msi").Length
        Write-Host "MSI installer size: $([math]::Round($msiSize/1MB, 2)) MB" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Host "Installation Requirements:" -ForegroundColor Yellow
    Write-Host "  - Windows 7 or later (64-bit)" -ForegroundColor White
    Write-Host "  - Administrator privileges required" -ForegroundColor White
    Write-Host "  - .NET Framework 4.0 or later" -ForegroundColor White
    Write-Host ""
    Write-Host "Installation Instructions:" -ForegroundColor Green
    Write-Host "  1. Right-click $APP_NAME-$APP_VERSION-setup.msi" -ForegroundColor White
    Write-Host "  2. Select 'Run as administrator'" -ForegroundColor White
    Write-Host "  3. Follow the installation wizard" -ForegroundColor White
    Write-Host "  4. Accept the license agreement" -ForegroundColor White
    Write-Host ""
    Write-Host "Uninstallation:" -ForegroundColor Green
    Write-Host "  - Use Control Panel > Programs and Features, OR" -ForegroundColor White
    Write-Host "  - Run uninstall_$APP_NAME.bat as Administrator" -ForegroundColor White
    Write-Host "==============================================" -ForegroundColor Blue
}

# Main execution

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
