; ReVideo Windows-Installer. Aufruf über scripts/build.sh:
;   makensis -DVERSION=x.y.z -DSTAGE=<install-tree> -DOUTFILE=<setup.exe> installer.nsi
Unicode true
SetCompressor /SOLID lzma

!include "MUI2.nsh"

!define APP "ReVideo"
!define PROGID "ReVideo.Video"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP}"
!define CAPS_KEY "Software\${APP}\Capabilities"

Name "${APP}"
OutFile "${OUTFILE}"
; Per-user install like the former Tauri build: no UAC prompt, HKCU only.
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "Software\${APP}" "InstallDir"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APP} Installer"
VIAddVersionKey "LegalCopyright" "Retry"

!define MUI_ICON "..\..\assets\icon.ico"
!define MUI_UNICON "..\..\assets\icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\bin\ReVideo.exe"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "German"

; Offers ReVideo under "Öffnen mit" without taking over the user's default player.
!macro ASSOC EXT
  WriteRegStr HKCU "Software\Classes\.${EXT}\OpenWithProgids" "${PROGID}" ""
  WriteRegStr HKCU "${CAPS_KEY}\FileAssociations" ".${EXT}" "${PROGID}"
!macroend
!macro UNASSOC EXT
  DeleteRegValue HKCU "Software\Classes\.${EXT}\OpenWithProgids" "${PROGID}"
  DeleteRegKey /ifempty HKCU "Software\Classes\.${EXT}\OpenWithProgids"
  DeleteRegKey /ifempty HKCU "Software\Classes\.${EXT}"
!macroend
!macro ALL_EXTS MACRO
  !insertmacro ${MACRO} "mp4"
  !insertmacro ${MACRO} "mkv"
  !insertmacro ${MACRO} "mov"
  !insertmacro ${MACRO} "avi"
  !insertmacro ${MACRO} "webm"
  !insertmacro ${MACRO} "flv"
  !insertmacro ${MACRO} "wmv"
  !insertmacro ${MACRO} "m4v"
  !insertmacro ${MACRO} "mpg"
  !insertmacro ${MACRO} "mpeg"
  !insertmacro ${MACRO} "ts"
  !insertmacro ${MACRO} "3gp"
!macroend

Section "Install"
  ; Old files of a previous version must not mix with the new plugin set.
  RMDir /r "$INSTDIR\bin"
  RMDir /r "$INSTDIR\lib"
  RMDir /r "$INSTDIR\libexec"
  SetOutPath "$INSTDIR"
  File /r "${STAGE}\*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateShortcut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\bin\ReVideo.exe"

  WriteRegStr HKCU "Software\${APP}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "Retry"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\bin\ReVideo.exe"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1

  WriteRegStr HKCU "Software\Classes\${PROGID}" "" "ReVideo Video"
  WriteRegStr HKCU "Software\Classes\${PROGID}\DefaultIcon" "" "$INSTDIR\bin\ReVideo.exe,0"
  WriteRegStr HKCU "Software\Classes\${PROGID}\shell\open\command" "" '"$INSTDIR\bin\ReVideo.exe" "%1"'
  WriteRegStr HKCU "${CAPS_KEY}" "ApplicationName" "${APP}"
  WriteRegStr HKCU "${CAPS_KEY}" "ApplicationDescription" "Video-Player und Trimmer"
  WriteRegStr HKCU "Software\RegisteredApplications" "${APP}" "${CAPS_KEY}"
  !insertmacro ALL_EXTS ASSOC

  System::Call "shell32::SHChangeNotify(i 0x08000000, i 0x1000, p 0, p 0)"
SectionEnd

Section "Uninstall"
  !insertmacro ALL_EXTS UNASSOC
  DeleteRegValue HKCU "Software\RegisteredApplications" "${APP}"
  DeleteRegKey HKCU "Software\Classes\${PROGID}"
  DeleteRegKey HKCU "Software\${APP}"
  DeleteRegKey HKCU "${UNINST_KEY}"
  Delete "$SMPROGRAMS\${APP}.lnk"
  RMDir /r "$INSTDIR"
  System::Call "shell32::SHChangeNotify(i 0x08000000, i 0x1000, p 0, p 0)"
SectionEnd
