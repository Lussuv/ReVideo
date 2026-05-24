!macro REGISTER_VIDEO_CAPABILITY EXT
  WriteRegStr SHCTX "${MANUPRODUCTKEY}\Capabilities\FileAssociations" ".${EXT}" "ReVideo Video"
!macroend

!macro UNREGISTER_VIDEO_CAPABILITY EXT
  DeleteRegValue SHCTX "${MANUPRODUCTKEY}\Capabilities\FileAssociations" ".${EXT}"
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

  DeleteRegKey /ifempty SHCTX "${MANUPRODUCTKEY}\Capabilities\FileAssociations"
  DeleteRegKey /ifempty SHCTX "${MANUPRODUCTKEY}\Capabilities"
!macroend
