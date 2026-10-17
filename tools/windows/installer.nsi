Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"
Name "怪好的医院"
OutFile "..\..\.build\installer\oddly-good-hospital-stage01-setup.exe"
InstallDir "$LOCALAPPDATA\Programs\oddly-good-hospital"
InstallDirRegKey HKCU "Software\oddly-good-hospital" "InstallDir"
RequestExecutionLevel user
ShowInstDetails show
ShowUninstDetails show
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"

Function .onInit
  SetShellVarContext current
  ReadRegStr $0 HKCU "Software\oddly-good-hospital" "InstallDir"
  StrCmp $0 "" +2
    Goto existing_install
  ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\oddly-good-hospital" "UninstallString"
  StrCmp $0 "" +2
    Goto existing_install
  IfFileExists "$SMPROGRAMS\怪好的医院\*.*" existing_install
  Return
  existing_install:
    IfSilent +2
      MessageBox MB_OK|MB_ICONEXCLAMATION "已检测到《怪好的医院》的现有安装或快捷方式。试验安装包不覆盖现有安装。"
    SetErrorLevel 2
    Abort
FunctionEnd

Function .onVerifyInstDir
  ${DirState} "$INSTDIR" $0
  StrCmp $0 1 0 +2
    Abort
FunctionEnd

Section "程序" SEC_MAIN
  ${DirState} "$INSTDIR" $0
  StrCmp $0 1 0 +4
    DetailPrint "目标目录不是空目录，安装已停止。"
    SetErrorLevel 2
    Abort
  SetOutPath "$INSTDIR"
  File "..\..\.build\windows\oddly-good-hospital.exe"
  File "..\..\.build\windows\oddly-good-hospital.pck"
  File "..\..\.build\windows\oddly_good_platform.windows.x86_64.dll"
  File "..\..\.build\windows\libgmp-10.dll"
  File "..\..\.build\windows\libmpfr-6.dll"
  File "..\..\.build\windows\libgcc_s_seh-1.dll"
  File "..\..\.build\windows\libwinpthread-1.dll"
  File "..\..\.build\windows\build-identity.json"
  SetOutPath "$INSTDIR\licenses"
  File "..\..\.build\windows\licenses\Godot-MIT.txt"
  File "..\..\.build\windows\licenses\Noto-Sans-CJK-OFL.txt"
  File "..\..\.build\windows\licenses\THIRD-PARTY-NOTICES.txt"
  File "..\..\.build\windows\licenses\SoPlex-Apache-2.0.txt"
  File "..\..\.build\windows\licenses\SCIP-Apache-2.0.txt"
  File "..\..\.build\windows\licenses\MPFR-LGPL-3.0.txt"
  File "..\..\.build\windows\licenses\mpfr-4.2.2-3-source.tar.zst"
  File "..\..\.build\windows\licenses\GCC-Runtime-Exception-3.1.txt"
  File "..\..\.build\windows\licenses\winpthreads-MIT-BSD.txt"
  File "..\..\.build\windows\licenses\gcc-16.2.0-6-source.tar.zst"
  File "..\..\.build\windows\licenses\Boost-1.0.txt"
  File "..\..\.build\windows\licenses\fmt-MIT.txt"
  File "..\..\.build\windows\licenses\GMP-LGPL-3.0.txt"
  File "..\..\.build\windows\licenses\GNU-GPL-3.0.txt"
  File "..\..\.build\windows\licenses\gmp-6.3.0-2-source.tar.zst"
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\oddly-good-hospital" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\oddly-good-hospital" "DisplayName" "怪好的医院"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\oddly-good-hospital" "DisplayVersion" "0.1.0-stage01"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\oddly-good-hospital" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\oddly-good-hospital" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\oddly-good-hospital" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\oddly-good-hospital" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\oddly-good-hospital" "NoRepair" 1
  CreateDirectory "$SMPROGRAMS\怪好的医院"
  CreateShortcut "$SMPROGRAMS\怪好的医院\怪好的医院.lnk" "$INSTDIR\oddly-good-hospital.exe"
  CreateShortcut "$SMPROGRAMS\怪好的医院\卸载.lnk" "$INSTDIR\Uninstall.exe"
SectionEnd
Section "Uninstall"
  ; Only this installation's known program files are removed. user:// is retained.
  SetShellVarContext current
  ReadRegStr $0 HKCU "Software\oddly-good-hospital" "InstallDir"
  StrCmp $0 "$INSTDIR" +4
    DetailPrint "卸载目录与安装登记不符，卸载已停止。"
    SetErrorLevel 2
    Abort
  Delete "$INSTDIR\oddly-good-hospital.exe"
  Delete "$INSTDIR\oddly-good-hospital.pck"
  Delete "$INSTDIR\oddly_good_platform.windows.x86_64.dll"
  Delete "$INSTDIR\libgmp-10.dll"
  Delete "$INSTDIR\libmpfr-6.dll"
  Delete "$INSTDIR\libgcc_s_seh-1.dll"
  Delete "$INSTDIR\libwinpthread-1.dll"
  Delete "$INSTDIR\build-identity.json"
  Delete "$INSTDIR\licenses\Godot-MIT.txt"
  Delete "$INSTDIR\licenses\Noto-Sans-CJK-OFL.txt"
  Delete "$INSTDIR\licenses\THIRD-PARTY-NOTICES.txt"
  Delete "$INSTDIR\licenses\SoPlex-Apache-2.0.txt"
  Delete "$INSTDIR\licenses\SCIP-Apache-2.0.txt"
  Delete "$INSTDIR\licenses\MPFR-LGPL-3.0.txt"
  Delete "$INSTDIR\licenses\mpfr-4.2.2-3-source.tar.zst"
  Delete "$INSTDIR\licenses\GCC-Runtime-Exception-3.1.txt"
  Delete "$INSTDIR\licenses\winpthreads-MIT-BSD.txt"
  Delete "$INSTDIR\licenses\gcc-16.2.0-6-source.tar.zst"
  Delete "$INSTDIR\licenses\Boost-1.0.txt"
  Delete "$INSTDIR\licenses\fmt-MIT.txt"
  Delete "$INSTDIR\licenses\GMP-LGPL-3.0.txt"
  Delete "$INSTDIR\licenses\GNU-GPL-3.0.txt"
  Delete "$INSTDIR\licenses\gmp-6.3.0-2-source.tar.zst"
  RMDir "$INSTDIR\licenses"
  Delete "$INSTDIR\Uninstall.exe"
  Delete "$SMPROGRAMS\怪好的医院\怪好的医院.lnk"
  Delete "$SMPROGRAMS\怪好的医院\卸载.lnk"
  RMDir "$SMPROGRAMS\怪好的医院"
  DeleteRegValue HKCU "Software\oddly-good-hospital" "InstallDir"
  DeleteRegKey /ifempty HKCU "Software\oddly-good-hospital"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\oddly-good-hospital"
  RMDir "$INSTDIR"
SectionEnd
