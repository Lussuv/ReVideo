!macro REGISTER_VIDEO_CAPABILITY EXT
  WriteRegStr SHCTX "${MANUPRODUCTKEY}\Capabilities\FileAssociations" ".${EXT}" "ReVideo Video"
!macroend

!macro UNREGISTER_VIDEO_CAPABILITY EXT
  DeleteRegValue SHCTX "${MANUPRODUCTKEY}\Capabilities\FileAssociations" ".${EXT}"
!macroend

!macro CLEAN_VIDEO_OPEN_WITH EXT
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.${EXT}\OpenWithProgids" "ReVideo Video"

  StrCpy $R1 0
  ClearErrors
  loop_open_with_${EXT}:
    EnumRegValue $R2 HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.${EXT}\OpenWithList" $R1
    IfErrors done_open_with_${EXT}
    ReadRegStr $R3 HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.${EXT}\OpenWithList" "$R2"
    StrCmp "$R3" "${MAINBINARYNAME}.exe" 0 +3
      DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.${EXT}\OpenWithList" "$R2"
      Goto loop_open_with_${EXT}
    StrCmp "$R3" "ReVideo.exe" 0 +3
      DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.${EXT}\OpenWithList" "$R2"
      Goto loop_open_with_${EXT}
    IntOp $R1 $R1 + 1
    Goto loop_open_with_${EXT}
  done_open_with_${EXT}:
  DeleteRegKey /ifempty HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.${EXT}\OpenWithList"

  ReadRegStr $R0 HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.${EXT}\UserChoice" "ProgId"
  StrCmp "$R0" "ReVideo Video" 0 +2
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.${EXT}\UserChoice"

  ReadRegStr $R0 SHCTX "Software\Classes\.${EXT}" ""
  StrCmp "$R0" "ReVideo Video" 0 +2
    DeleteRegValue SHCTX "Software\Classes\.${EXT}" ""
  DeleteRegValue SHCTX "Software\Classes\.${EXT}" "ReVideo Video_backup"
  DeleteRegKey /ifempty SHCTX "Software\Classes\.${EXT}"
!macroend

!macro CLEAN_REVIDEO_APPLICATION_KEYS
  DeleteRegKey SHCTX "Software\Classes\Applications\${MAINBINARYNAME}.exe"
  DeleteRegKey HKCU "Software\Classes\Applications\${MAINBINARYNAME}.exe"
  DeleteRegKey HKLM "Software\Classes\Applications\${MAINBINARYNAME}.exe"
  DeleteRegKey SHCTX "Software\Classes\Applications\ReVideo.exe"
  DeleteRegKey HKCU "Software\Classes\Applications\ReVideo.exe"
  DeleteRegKey HKLM "Software\Classes\Applications\ReVideo.exe"
!macroend

!macro NSIS_HOOK_POSTINSTALL
  WriteRegStr SHCTX "Software\RegisteredApplications" "${PRODUCTNAME}" "${MANUPRODUCTKEY}\Capabilities"
  WriteRegStr SHCTX "${MANUPRODUCTKEY}\Capabilities" "ApplicationName" "${PRODUCTNAME}"
  WriteRegStr SHCTX "${MANUPRODUCTKEY}\Capabilities" "ApplicationDescription" "Schoener, schneller Video-Trimmer fuer Windows"

  !insertmacro REGISTER_VIDEO_CAPABILITY "mp4"
  !insertmacro REGISTER_VIDEO_CAPABILITY "mkv"
  !insertmacro REGISTER_VIDEO_CAPABILITY "mov"
  !insertmacro REGISTER_VIDEO_CAPABILITY "avi"
  !insertmacro REGISTER_VIDEO_CAPABILITY "webm"
  !insertmacro REGISTER_VIDEO_CAPABILITY "flv"
  !insertmacro REGISTER_VIDEO_CAPABILITY "wmv"
  !insertmacro REGISTER_VIDEO_CAPABILITY "m4v"
  !insertmacro REGISTER_VIDEO_CAPABILITY "mpg"
  !insertmacro REGISTER_VIDEO_CAPABILITY "mpeg"
  !insertmacro REGISTER_VIDEO_CAPABILITY "ts"
  !insertmacro REGISTER_VIDEO_CAPABILITY "3gp"
!macroend

!macro NSIS_HOOK_POSTUNINSTALL
  DeleteRegValue SHCTX "Software\RegisteredApplications" "${PRODUCTNAME}"

  !insertmacro UNREGISTER_VIDEO_CAPABILITY "mp4"
  !insertmacro UNREGISTER_VIDEO_CAPABILITY "mkv"
  !insertmacro UNREGISTER_VIDEO_CAPABILITY "mov"
  !insertmacro UNREGISTER_VIDEO_CAPABILITY "avi"
  !insertmacro UNREGISTER_VIDEO_CAPABILITY "webm"
  !insertmacro UNREGISTER_VIDEO_CAPABILITY "flv"
  !insertmacro UNREGISTER_VIDEO_CAPABILITY "wmv"
  !insertmacro UNREGISTER_VIDEO_CAPABILITY "m4v"
  !insertmacro UNREGISTER_VIDEO_CAPABILITY "mpg"
  !insertmacro UNREGISTER_VIDEO_CAPABILITY "mpeg"
  !insertmacro UNREGISTER_VIDEO_CAPABILITY "ts"
  !insertmacro UNREGISTER_VIDEO_CAPABILITY "3gp"

  !insertmacro CLEAN_VIDEO_OPEN_WITH "mp4"
  !insertmacro CLEAN_VIDEO_OPEN_WITH "mkv"
  !insertmacro CLEAN_VIDEO_OPEN_WITH "mov"
  !insertmacro CLEAN_VIDEO_OPEN_WITH "avi"
  !insertmacro CLEAN_VIDEO_OPEN_WITH "webm"
  !insertmacro CLEAN_VIDEO_OPEN_WITH "flv"
  !insertmacro CLEAN_VIDEO_OPEN_WITH "wmv"
  !insertmacro CLEAN_VIDEO_OPEN_WITH "m4v"
  !insertmacro CLEAN_VIDEO_OPEN_WITH "mpg"
  !insertmacro CLEAN_VIDEO_OPEN_WITH "mpeg"
  !insertmacro CLEAN_VIDEO_OPEN_WITH "ts"
  !insertmacro CLEAN_VIDEO_OPEN_WITH "3gp"
  !insertmacro CLEAN_REVIDEO_APPLICATION_KEYS

  DeleteRegKey /ifempty SHCTX "${MANUPRODUCTKEY}\Capabilities\FileAssociations"
  DeleteRegKey /ifempty SHCTX "${MANUPRODUCTKEY}\Capabilities"
  DeleteRegKey /ifempty SHCTX "${MANUPRODUCTKEY}"
  DeleteRegKey /ifempty SHCTX "${MANUKEY}"

  System::Call "shell32::SHChangeNotify(i,i,i,i) (0x08000000, 0x1000, 0, 0)"
!macroend
