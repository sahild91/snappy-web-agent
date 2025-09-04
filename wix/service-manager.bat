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
