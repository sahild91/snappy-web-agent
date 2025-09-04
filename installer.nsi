; Snappy Web Agent NSIS Installer Script
; Compatible with NSIS 3.x and works great with Wine cross-compilation

!define APP_NAME "Snappy Web Agent"
!define APP_VERSION "1.0.1"
!define APP_PUBLISHER "YuduRobotics"
!define APP_URL "https://yudurobotics.com"
!define APP_EXECUTABLE "snappy-web-agent.exe"
!define SERVICE_NAME "SnappyWebAgent"
!define SERVICE_DISPLAY_NAME "Snappy Web Agent Service"

; Include necessary headers
!include "MUI2.nsh"
!include "x64.nsh"

; General settings
Name "${APP_NAME}"
OutFile "snappy-web-agent-${APP_VERSION}-setup.exe"
InstallDir "$PROGRAMFILES64\${APP_PUBLISHER}\${APP_NAME}"
InstallDirRegKey HKLM "Software\${APP_PUBLISHER}\${APP_NAME}" "InstallPath"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

; Version info
VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey "LegalCopyright" "© ${APP_PUBLISHER}"
VIAddVersionKey "FileDescription" "${APP_NAME} Installer"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"

; Interface Settings
!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\modern-uninstall.ico"

; Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "LICENSE.rtf"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; Languages
!insertmacro MUI_LANGUAGE "English"

; Installation sections
Section "Core Application" SecCore
  SectionIn RO
  SetOutPath "$INSTDIR"
  File "build\x64\${APP_EXECUTABLE}"
  File "README.md"
  File "LICENSE.rtf"
  File "wix\service-manager.bat"
  File "snappy.exe"
  
  ; Create service management scripts
  FileOpen $0 "$INSTDIR\install-service.bat" w
  FileWrite $0 "@echo off$\r$\n"
  FileWrite $0 "echo Installing ${APP_NAME} Service...$\r$\n"
  FileWrite $0 "cd /d %~dp0$\r$\n"
  FileWrite $0 "service-manager.bat install$\r$\n"
  FileWrite $0 "service-manager.bat start$\r$\n"
  FileWrite $0 "echo Service installed and configured to run in background.$\r$\n"
  FileWrite $0 "echo The service will automatically start when Windows boots.$\r$\n"
  FileWrite $0 "echo Press any key to close this window...$\r$\n"
  FileWrite $0 "pause >nul$\r$\n"
  FileClose $0
  
  FileOpen $0 "$INSTDIR\uninstall-service.bat" w
  FileWrite $0 "@echo off$\r$\n"
  FileWrite $0 "echo Uninstalling ${APP_NAME} Service...$\r$\n"
  FileWrite $0 "cd /d %~dp0$\r$\n"
  FileWrite $0 "service-manager.bat stop$\r$\n"
  FileWrite $0 "service-manager.bat uninstall$\r$\n"
  FileWrite $0 "echo Service uninstalled.$\r$\n"
  FileWrite $0 "echo Press any key to close this window...$\r$\n"
  FileWrite $0 "pause >nul$\r$\n"
  FileClose $0
  
  ; Write registry keys (upgrade-in-place)
  WriteRegStr HKLM "Software\${APP_PUBLISHER}\${APP_NAME}" "InstallPath" "$INSTDIR"
  WriteRegStr HKLM "Software\${APP_PUBLISHER}\${APP_NAME}" "Version" "${APP_VERSION}"
  WriteRegStr HKLM "Software\${APP_PUBLISHER}\${APP_NAME}" "ServiceName" "${SERVICE_NAME}"
  ; Create uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  ; Single Add/Remove Programs entry
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "HelpLink" "${APP_URL}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayVersion" "${APP_VERSION}"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "NoRepair" 1

  DetailPrint "Launching snappy.exe..."
  Exec '"$INSTDIR\snappy.exe"'
SectionEnd

Section "Windows Service" SecService
  DetailPrint "Installing Windows Service ${SERVICE_NAME} (upgrade mode)..."
  ; Stop/delete existing service if present (ignore errors)
  ExecWait 'sc stop "${SERVICE_NAME}"' $0
  ExecWait 'sc delete "${SERVICE_NAME}"' $1
  ExecWait 'sc create "${SERVICE_NAME}" binPath= "$INSTDIR\${APP_EXECUTABLE} --service" DisplayName= "${SERVICE_DISPLAY_NAME}" start= auto type= own error= normal' $2
  ${If} $2 == 0
    DetailPrint "Service created"
    ExecWait 'sc config "${SERVICE_NAME}" start= auto' $3
    ExecWait 'sc failure "${SERVICE_NAME}" reset= 86400 actions= restart/5000/restart/10000/restart/30000' $4
    ExecWait 'sc description "${SERVICE_NAME}" "Snappy Web Agent Service - Handles communication between web applications and hardware devices"' $5
    ExecWait 'sc start "${SERVICE_NAME}"' $6
    ${If} $6 == 0
      DetailPrint "Service started"
    ${Else}
      DetailPrint "Service will start on next boot"
    ${EndIf}
  ${Else}
    DetailPrint "Failed to create service (Error $2)"
  ${EndIf}
SectionEnd

Section "Start Menu Shortcuts" SecStartMenu
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME} Service Manager.lnk" "$INSTDIR\service-manager.bat" "" "$INSTDIR\${APP_EXECUTABLE}" 0
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\Install Service.lnk" "$INSTDIR\install-service.bat" "" "$INSTDIR\${APP_EXECUTABLE}" 0
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\Uninstall Service.lnk" "$INSTDIR\uninstall-service.bat" "" "$INSTDIR\${APP_EXECUTABLE}" 0
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\Documentation.lnk" "$INSTDIR\README.md"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

; Section descriptions
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecCore} "Core application files (required)"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecService} "Install and start as Windows Service (recommended)"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecStartMenu} "Create Start Menu shortcuts for easy access"
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; Functions
Function .onInit
  ; Check if we're running on 64-bit Windows
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "This application requires 64-bit Windows."
    Abort
  ${EndIf}
  
  ; Check for administrator privileges
  UserInfo::GetAccountType
  Pop $0
  ${If} $0 != "admin"
    MessageBox MB_OK|MB_ICONSTOP "Administrator privileges are required to install this application."
    Abort
  ${EndIf}
FunctionEnd

; Uninstaller sections
Section "Uninstall"
  DetailPrint "Stopping service ${SERVICE_NAME}..."
  ExecWait 'sc stop "${SERVICE_NAME}"' $0
  Sleep 3000
  DetailPrint "Removing service ${SERVICE_NAME}..."
  ExecWait 'sc delete "${SERVICE_NAME}"' $1
  Delete "$INSTDIR\${APP_EXECUTABLE}"
  Delete "$INSTDIR\snappy.exe"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\LICENSE.rtf"
  Delete "$INSTDIR\service-manager.bat"
  Delete "$INSTDIR\install-service.bat"
  Delete "$INSTDIR\uninstall-service.bat"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  RMDir "$PROGRAMFILES64\${APP_PUBLISHER}" ; only if empty
  RMDir /r "$SMPROGRAMS\${APP_NAME}"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"
  DeleteRegKey HKLM "Software\${APP_PUBLISHER}\${APP_NAME}"
SectionEnd

Function un.onInit
  ; Confirm uninstallation
  MessageBox MB_YESNO|MB_ICONQUESTION "Are you sure you want to remove ${APP_NAME} and all of its components?" IDYES +2
  Abort
FunctionEnd
