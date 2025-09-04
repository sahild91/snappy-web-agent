@echo off
REM Snappy Web Agent - Windows Universal Build Script
REM Creates x64 and x86 binaries and packages them into an MSI installer with Windows Service setup

setlocal enabledelayedexpansion

REM Configuration
set APP_NAME=snappy-web-agent
set APP_VERSION=1.0.0
set COMPANY_NAME=YuduRobotics
set BUILD_DIR=build
set DIST_DIR=dist
set WIX_DIR=wix
set SERVICE_NAME=SnappyWebAgent
set SERVICE_DISPLAY_NAME=Snappy Web Agent Service

REM Colors for output (Windows compatible)
set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "BLUE=[94m"
set "NC=[0m"

echo %BLUE%[%date% %time%]%NC% Starting Windows universal build process...

REM Check dependencies
echo %BLUE%[%date% %time%]%NC% Checking dependencies...

where cargo >nul 2>&1
if errorlevel 1 (
    echo %RED%Error:%NC% Cargo is not installed. Please install Rust.
    exit /b 1
)

where rustup >nul 2>&1
if errorlevel 1 (
    echo %RED%Error:%NC% Rustup is not installed. Please install Rust.
    exit /b 1
)

where candle.exe >nul 2>&1
if errorlevel 1 (
    echo %RED%Error:%NC% WiX Toolset is not installed. Please install WiX Toolset v3.
    echo Download from: https://wixtoolset.org/releases/
    exit /b 1
)

where light.exe >nul 2>&1
if errorlevel 1 (
    echo %RED%Error:%NC% WiX Light tool is not found. Please ensure WiX is in PATH.
    exit /b 1
)

echo %GREEN%✓%NC% All dependencies found

REM Add Rust targets
echo %BLUE%[%date% %time%]%NC% Adding Rust targets for cross-compilation...
rustup target add x86_64-pc-windows-msvc
rustup target add i686-pc-windows-msvc
echo %GREEN%✓%NC% Rust targets added

REM Clean previous builds
echo %BLUE%[%date% %time%]%NC% Cleaning previous builds...
if exist target\x86_64-pc-windows-msvc\release\%APP_NAME%.exe del /q target\x86_64-pc-windows-msvc\release\%APP_NAME%.exe
if exist target\i686-pc-windows-msvc\release\%APP_NAME%.exe del /q target\i686-pc-windows-msvc\release\%APP_NAME%.exe
if exist %BUILD_DIR% rd /s /q %BUILD_DIR%
if exist %DIST_DIR% rd /s /q %DIST_DIR%
if exist %WIX_DIR% rd /s /q %WIX_DIR%
if exist *.msi del /q *.msi
cargo clean
echo %GREEN%✓%NC% Clean completed

REM Build for x64
echo %BLUE%[%date% %time%]%NC% Building for x64 (Windows 64-bit)...
cargo build --release --target x86_64-pc-windows-msvc
if errorlevel 1 (
    echo %RED%Error:%NC% x64 build failed
    exit /b 1
)
echo %GREEN%✓%NC% x64 build completed

REM Build for x86
echo %BLUE%[%date% %time%]%NC% Building for x86 (Windows 32-bit)...
cargo build --release --target i686-pc-windows-msvc
if errorlevel 1 (
    echo %RED%Error:%NC% x86 build failed
    exit /b 1
)
echo %GREEN%✓%NC% x86 build completed

REM Create build directory structure
echo %BLUE%[%date% %time%]%NC% Creating build directory structure...
mkdir %BUILD_DIR%
mkdir %BUILD_DIR%\x64
mkdir %BUILD_DIR%\x86

copy target\x86_64-pc-windows-msvc\release\%APP_NAME%.exe %BUILD_DIR%\x64\
copy target\i686-pc-windows-msvc\release\%APP_NAME%.exe %BUILD_DIR%\x86\

echo %GREEN%✓%NC% Build directory structure created

REM Create installation directory structure
echo %BLUE%[%date% %time%]%NC% Creating installation directory structure...
mkdir %DIST_DIR%
mkdir %DIST_DIR%\x64
mkdir %DIST_DIR%\x86
mkdir %DIST_DIR%\docs

REM Copy binaries
copy %BUILD_DIR%\x64\%APP_NAME%.exe %DIST_DIR%\x64\
copy %BUILD_DIR%\x86\%APP_NAME%.exe %DIST_DIR%\x86\

REM Copy documentation
copy README.md %DIST_DIR%\docs\

echo %GREEN%✓%NC% Installation structure created

REM Create Windows Service wrapper script
echo %BLUE%[%date% %time%]%NC% Creating service wrapper...
mkdir %WIX_DIR%

(
echo @echo off
echo REM Snappy Web Agent Service Wrapper
echo REM This script manages the Snappy Web Agent as a Windows Service
echo.
echo set SERVICE_NAME=%SERVICE_NAME%
echo set APP_NAME=%APP_NAME%
echo set INSTALL_DIR=%%PROGRAMFILES%%\%COMPANY_NAME%\Snappy Web Agent
echo.
echo if "%%1"=="install" goto :install
echo if "%%1"=="uninstall" goto :uninstall
echo if "%%1"=="start" goto :start
echo if "%%1"=="stop" goto :stop
echo if "%%1"=="restart" goto :restart
echo.
echo echo Usage: %%0 [install^|uninstall^|start^|stop^|restart]
echo goto :eof
echo.
echo :install
echo echo Installing %%SERVICE_NAME%% service...
echo sc create "%%SERVICE_NAME%%" binPath= "\"%%INSTALL_DIR%%\%%APP_NAME%%.exe\"" DisplayName= "%SERVICE_DISPLAY_NAME%" start= auto
echo if %%errorlevel%% equ 0 ^(
echo     echo Service installed successfully
echo     echo Starting service...
echo     sc start "%%SERVICE_NAME%%"
echo ^) else ^(
echo     echo Failed to install service
echo ^)
echo goto :eof
echo.
echo :uninstall
echo echo Stopping %%SERVICE_NAME%% service...
echo sc stop "%%SERVICE_NAME%%"
echo echo Uninstalling %%SERVICE_NAME%% service...
echo sc delete "%%SERVICE_NAME%%"
echo if %%errorlevel%% equ 0 ^(
echo     echo Service uninstalled successfully
echo ^) else ^(
echo     echo Failed to uninstall service
echo ^)
echo goto :eof
echo.
echo :start
echo echo Starting %%SERVICE_NAME%% service...
echo sc start "%%SERVICE_NAME%%"
echo goto :eof
echo.
echo :stop
echo echo Stopping %%SERVICE_NAME%% service...
echo sc stop "%%SERVICE_NAME%%"
echo goto :eof
echo.
echo :restart
echo echo Restarting %%SERVICE_NAME%% service...
echo sc stop "%%SERVICE_NAME%%"
echo timeout /t 3 /nobreak ^>nul
echo sc start "%%SERVICE_NAME%%"
echo goto :eof
) > %WIX_DIR%\service-manager.bat

echo %GREEN%✓%NC% Service wrapper created

REM Create WiX source file
echo %BLUE%[%date% %time%]%NC% Creating WiX installer source...

(
echo ^<?xml version="1.0" encoding="UTF-8"?^>
echo ^<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi"^>
echo   ^<Product Id="*" Name="Snappy Web Agent" Language="1033" Version="%APP_VERSION%" Manufacturer="%COMPANY_NAME%" UpgradeCode="12345678-1234-1234-1234-123456789012"^>
echo     ^<Package InstallerVersion="200" Compressed="yes" InstallScope="perMachine" /^>
echo.
echo     ^<MajorUpgrade DowngradeErrorMessage="A newer version of [ProductName] is already installed." /^>
echo     ^<MediaTemplate EmbedCab="yes" /^>
echo.
echo     ^<!-- Directory Structure --^>
echo     ^<Directory Id="TARGETDIR" Name="SourceDir"^>
echo       ^<Directory Id="ProgramFilesFolder"^>
echo         ^<Directory Id="CompanyFolder" Name="%COMPANY_NAME%"^>
echo           ^<Directory Id="INSTALLFOLDER" Name="Snappy Web Agent"^>
echo             ^<Directory Id="DocsFolder" Name="docs" /^>
echo           ^</Directory^>
echo         ^</Directory^>
echo       ^</Directory^>
echo       ^<Directory Id="ProgramMenuFolder"^>
echo         ^<Directory Id="ApplicationProgramsFolder" Name="Snappy Web Agent" /^>
echo       ^</Directory^>
echo     ^</Directory^>
echo.
echo     ^<!-- Components --^>
echo     ^<ComponentGroup Id="ProductComponents" Directory="INSTALLFOLDER"^>
echo       ^<!-- Main executable ^(architecture-specific^) --^>
echo       ^<Component Id="MainExecutable" Guid="*"^>
echo         ^<Condition^>^<![CDATA[VersionNT64]^]^>^</Condition^>
echo         ^<File Id="MainExeX64" Source="dist\x64\%APP_NAME%.exe" KeyPath="yes" /^>
echo       ^</Component^>
echo       ^<Component Id="MainExecutableX86" Guid="*"^>
echo         ^<Condition^>^<![CDATA[NOT VersionNT64]^]^>^</Condition^>
echo         ^<File Id="MainExeX86" Source="dist\x86\%APP_NAME%.exe" KeyPath="yes" /^>
echo       ^</Component^>
echo.
echo       ^<!-- Service Manager Script --^>
echo       ^<Component Id="ServiceManager" Guid="*"^>
echo         ^<File Id="ServiceManagerBat" Source="%WIX_DIR%\service-manager.bat" KeyPath="yes" /^>
echo       ^</Component^>
echo.
echo       ^<!-- Documentation --^>
echo       ^<Component Id="Documentation" Guid="*" Directory="DocsFolder"^>
echo         ^<File Id="ReadmeFile" Source="dist\docs\README.md" KeyPath="yes" /^>
echo       ^</Component^>
echo     ^</ComponentGroup^>
echo.
echo     ^<!-- Start Menu Shortcuts --^>
echo     ^<DirectoryRef Id="ApplicationProgramsFolder"^>
echo       ^<Component Id="ApplicationShortcut" Guid="*"^>
echo         ^<Shortcut Id="ServiceManagerShortcut"
echo                   Name="Snappy Web Agent Service Manager"
echo                   Description="Manage Snappy Web Agent Service"
echo                   Target="[INSTALLFOLDER]service-manager.bat"
echo                   WorkingDirectory="INSTALLFOLDER" /^>
echo         ^<RemoveFolder Id="ApplicationProgramsFolder" On="uninstall" /^>
echo         ^<RegistryValue Root="HKCU" Key="Software\%COMPANY_NAME%\Snappy Web Agent" Name="installed" Type="integer" Value="1" KeyPath="yes" /^>
echo       ^</Component^>
echo     ^</DirectoryRef^>
echo.
echo     ^<!-- Windows Service --^>
echo     ^<Component Id="WindowsService" Guid="*" Directory="INSTALLFOLDER"^>
echo       ^<ServiceInstall Id="SnappyWebAgentService"
echo                       Name="%SERVICE_NAME%"
echo                       DisplayName="%SERVICE_DISPLAY_NAME%"
echo                       Description="Snappy Web Agent - Serial device data collection and streaming service"
echo                       Type="ownProcess"
echo                       Start="auto"
echo                       Account="LocalSystem"
echo                       ErrorControl="normal"
echo                       Interactive="no" /^>
echo       ^<ServiceControl Id="StartService" Name="%SERVICE_NAME%" Start="install" Stop="both" Remove="uninstall" Wait="yes" /^>
echo     ^</Component^>
echo.
echo     ^<!-- Custom Actions --^>
echo     ^<CustomAction Id="CreateLogDirectory" Directory="TARGETDIR" ExeName="cmd.exe" Execute="deferred" Impersonate="no"
echo                   ExeCommand="/c mkdir &quot;[CommonAppDataFolder]%COMPANY_NAME%\Snappy Web Agent\logs&quot; 2^>nul" /^>
echo.
echo     ^<!-- Install Sequence --^>
echo     ^<InstallExecuteSequence^>
echo       ^<Custom Action="CreateLogDirectory" After="InstallFiles"^>NOT Installed^</Custom^>
echo     ^</InstallExecuteSequence^>
echo.
echo     ^<!-- Feature Definition --^>
echo     ^<Feature Id="ProductFeature" Title="Snappy Web Agent" Level="1"^>
echo       ^<ComponentGroupRef Id="ProductComponents" /^>
echo       ^<ComponentRef Id="ApplicationShortcut" /^>
echo       ^<ComponentRef Id="WindowsService" /^>
echo     ^</Feature^>
echo.
echo     ^<!-- UI Configuration --^>
echo     ^<Property Id="WIXUI_INSTALLDIR" Value="INSTALLFOLDER" /^>
echo     ^<UIRef Id="WixUI_InstallDir" /^>
echo     ^<UIRef Id="WixUI_ErrorProgressText" /^>
echo.
echo   ^</Product^>
echo ^</Wix^>
) > %WIX_DIR%\%APP_NAME%.wxs

echo %GREEN%✓%NC% WiX source created

REM Compile WiX installer
echo %BLUE%[%date% %time%]%NC% Compiling MSI installer...

cd %WIX_DIR%
candle.exe -out %APP_NAME%.wixobj %APP_NAME%.wxs
if errorlevel 1 (
    echo %RED%Error:%NC% WiX compilation failed
    cd ..
    exit /b 1
)

light.exe -out ..\%APP_NAME%-%APP_VERSION%-setup.msi %APP_NAME%.wixobj -ext WixUIExtension
if errorlevel 1 (
    echo %RED%Error:%NC% WiX linking failed
    cd ..
    exit /b 1
)

cd ..
echo %GREEN%✓%NC% MSI installer created: %APP_NAME%-%APP_VERSION%-setup.msi

REM Create uninstaller script
echo %BLUE%[%date% %time%]%NC% Creating uninstaller script...

(
echo @echo off
echo REM Snappy Web Agent Uninstaller
echo.
echo echo Uninstalling Snappy Web Agent...
echo.
echo REM Stop and remove service
echo echo Stopping service...
echo sc stop "%SERVICE_NAME%" 2^>nul
echo echo Removing service...
echo sc delete "%SERVICE_NAME%" 2^>nul
echo.
echo REM Uninstall via MSI
echo echo Uninstalling application...
echo msiexec /x {ProductCode} /quiet /norestart
echo.
echo echo Snappy Web Agent has been uninstalled.
echo pause
) > uninstall_%APP_NAME%.bat

echo %GREEN%✓%NC% Uninstaller created: uninstall_%APP_NAME%.bat

REM Create installation guide
echo %BLUE%[%date% %time%]%NC% Creating installation guide...

(
echo # Snappy Web Agent - Windows Installation Guide
echo.
echo ## System Requirements
echo - Windows 7/8/10/11 ^(32-bit or 64-bit^)
echo - Administrator privileges for service installation
echo - Available port starting from 8436
echo.
echo ## Installation
echo.
echo ### Option 1: MSI Installer ^(Recommended^)
echo 1. Double-click `%APP_NAME%-%APP_VERSION%-setup.msi`
echo 2. Follow the installation wizard
echo 3. The service will be automatically installed and started
echo.
echo ### Option 2: Manual Installation
echo 1. Extract files to desired location
echo 2. Run `service-manager.bat install` as Administrator
echo 3. Run `service-manager.bat start` to start the service
echo.
echo ## Service Management
echo.
echo The Snappy Web Agent runs as a Windows Service. You can manage it using:
echo.
echo ### Service Manager Script
echo ```batch
echo # Install service
echo service-manager.bat install
echo.
echo # Start service
echo service-manager.bat start
echo.
echo # Stop service
echo service-manager.bat stop
echo.
echo # Restart service
echo service-manager.bat restart
echo.
echo # Uninstall service
echo service-manager.bat uninstall
echo ```
echo.
echo ### Windows Services Manager
echo 1. Press `Win + R`, type `services.msc`, press Enter
echo 2. Find "%SERVICE_DISPLAY_NAME%" in the list
echo 3. Right-click to Start, Stop, or configure the service
echo.
echo ### Command Line
echo ```batch
echo # Start service
echo sc start "%SERVICE_NAME%"
echo.
echo # Stop service
echo sc stop "%SERVICE_NAME%"
echo.
echo # Check service status
echo sc query "%SERVICE_NAME%"
echo ```
echo.
echo ## Configuration
echo.
echo The service will automatically:
echo - Find an available port starting from 8436
echo - Start on system boot
echo - Restart automatically if it crashes
echo - Log to Windows Event Log
echo.
echo ## Logs
echo.
echo Service logs can be found in:
echo - Windows Event Viewer ^(Windows Logs ^> Application^)
echo - Application data folder: `%%PROGRAMDATA%%\%COMPANY_NAME%\Snappy Web Agent\logs\`
echo.
echo ## Uninstallation
echo.
echo ### Option 1: Control Panel
echo 1. Go to Control Panel ^> Programs and Features
echo 2. Find "Snappy Web Agent" and click Uninstall
echo.
echo ### Option 2: Uninstaller Script
echo Run `uninstall_%APP_NAME%.bat` as Administrator
echo.
echo ## Troubleshooting
echo.
echo ### Service won't start
echo 1. Check Windows Event Log for error details
echo 2. Ensure no other application is using ports 8436-8535
echo 3. Run `service-manager.bat start` as Administrator
echo.
echo ### Port conflicts
echo The agent automatically finds available ports. If all ports in range are busy:
echo 1. Stop other applications using those ports
echo 2. Restart the service
echo.
echo ### Permission issues
echo Ensure the service is running with proper permissions:
echo 1. Open Services Manager ^(`services.msc`^)
echo 2. Right-click "%SERVICE_DISPLAY_NAME%" ^> Properties
echo 3. Go to "Log On" tab
echo 4. Ensure "Local System account" is selected
echo.
) > Windows_Installation_Guide.md

echo %GREEN%✓%NC% Installation guide created: Windows_Installation_Guide.md

REM Display build summary
echo.
echo %BLUE%[%date% %time%]%NC% Build Summary
echo ==============================================
echo %GREEN%✓%NC% x64 binary: %BUILD_DIR%\x64\%APP_NAME%.exe
echo %GREEN%✓%NC% x86 binary: %BUILD_DIR%\x86\%APP_NAME%.exe
echo %GREEN%✓%NC% MSI installer: %APP_NAME%-%APP_VERSION%-setup.msi
echo %GREEN%✓%NC% Uninstaller: uninstall_%APP_NAME%.bat
echo %GREEN%✓%NC% Service manager: %WIX_DIR%\service-manager.bat
echo %GREEN%✓%NC% Installation guide: Windows_Installation_Guide.md
echo.
echo Binary sizes:
for %%f in (%BUILD_DIR%\x64\%APP_NAME%.exe) do echo   x64: %%~zf bytes
for %%f in (%BUILD_DIR%\x86\%APP_NAME%.exe) do echo   x86: %%~zf bytes
echo.
echo MSI installer size:
for %%f in (%APP_NAME%-%APP_VERSION%-setup.msi) do echo   %%~zf bytes
echo.
echo To install: Double-click %APP_NAME%-%APP_VERSION%-setup.msi
echo To uninstall: Run uninstall_%APP_NAME%.bat as Administrator
echo ==============================================

echo %GREEN%✓%NC% Build process completed successfully!
echo.
pause
