@echo off
setlocal
rem ============================================================================
rem Builds TeleRehabSetup-<version>.exe - the Windows installer.
rem
rem Usage (from anywhere):
rem   installer\build_installer.cmd                       dashboard only
rem   installer\build_installer.cmd "D:\SmartGameBuild"   bundle the Unity app
rem   installer\build_installer.cmd "" nobuild            reuse existing payload
rem
rem A .cmd (not .ps1) on purpose: this machine's Group Policy enforces
rem AllSigned for PowerShell scripts; batch files are unaffected.
rem
rem Prerequisites:
rem   - Flutter SDK on PATH
rem   - Inno Setup 6:  winget install JRSoftware.InnoSetup
rem   - optional: a Unity Windows player build (Unity: File - Build Settings -
rem     Windows x86_64 - Build into an empty folder) passed as argument 1
rem ============================================================================

set "INSTALLER_DIR=%~dp0"
set "REPO_ROOT=%INSTALLER_DIR%.."
set "UNITY_BUILD=%~1"
set "SKIPBUILD="
if /i "%~1"=="nobuild" ( set "UNITY_BUILD=" & set "SKIPBUILD=1" )
if /i "%~2"=="nobuild" set "SKIPBUILD=1"

echo === TeleRehab installer build ===

rem -- 1. Flutter release build ------------------------------------------------
if defined SKIPBUILD (
    echo [1/4] flutter build skipped ^(nobuild^)
) else (
    echo [1/4] flutter build windows --release
    pushd "%REPO_ROOT%"
    call flutter build windows --release
    if errorlevel 1 ( popd & echo ERROR: flutter build failed & exit /b 1 )
    popd
)
if not exist "%REPO_ROOT%\build\windows\x64\runner\Release\telehealth_dashboard.exe" (
    echo ERROR: dashboard payload not found - did the Flutter build succeed?
    exit /b 1
)

rem -- 2. Unity payload ----------------------------------------------------------
if "%UNITY_BUILD%"=="" (
    if exist "%INSTALLER_DIR%unity_payload" (
        echo [2/4] reusing existing installer\unity_payload
    ) else (
        echo [2/4] no Unity build given - dashboard-only installer
    )
) else (
    echo [2/4] copying Unity build from "%UNITY_BUILD%"
    if not exist "%UNITY_BUILD%" ( echo ERROR: folder not found: %UNITY_BUILD% & exit /b 1 )
    if exist "%INSTALLER_DIR%unity_payload" rmdir /s /q "%INSTALLER_DIR%unity_payload"
    rem /XD skips Unity's debug-symbol folders; robocopy exit codes ^>=8 = failure
    robocopy "%UNITY_BUILD%" "%INSTALLER_DIR%unity_payload" /E /NFL /NDL /NJH /NJS ^
        /XD "*_BackUpThisFolder_ButDontShipItWithYourGame" "*_BurstDebugInformation_DoNotShip" >nul
    if errorlevel 8 ( echo ERROR: robocopy failed & exit /b 1 )
)

rem -- 3. VC++ redistributable --------------------------------------------------
if exist "%INSTALLER_DIR%redist\vc_redist.x64.exe" (
    echo [3/4] VC++ redist already present
) else (
    echo [3/4] downloading vc_redist.x64.exe
    if not exist "%INSTALLER_DIR%redist" mkdir "%INSTALLER_DIR%redist"
    curl -L -o "%INSTALLER_DIR%redist\vc_redist.x64.exe" https://aka.ms/vs/17/release/vc_redist.x64.exe
    if errorlevel 1 (
        echo WARNING: download failed - building WITHOUT the VC++ runtime.
        echo          Target machines then need it preinstalled.
        del /q "%INSTALLER_DIR%redist\vc_redist.x64.exe" 2>nul
    )
)

rem -- 4. Compile with Inno Setup -------------------------------------------------
set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if exist "%LocalAppData%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LocalAppData%\Programs\Inno Setup 6\ISCC.exe"
if "%ISCC%"=="" (
    echo ERROR: Inno Setup not found. Install it with:  winget install JRSoftware.InnoSetup
    exit /b 1
)
echo [4/4] compiling installer
"%ISCC%" "%INSTALLER_DIR%telerehab.iss"
if errorlevel 1 ( echo ERROR: ISCC failed & exit /b 1 )

echo.
echo DONE - installer written to %INSTALLER_DIR%Output\
for %%F in ("%INSTALLER_DIR%Output\TeleRehabSetup-*.exe") do (
    echo %%~nxF
    rem SHA-256 printed so it can be handed to an IT/security team for an
    rem allow-list entry when Defender flags the unsigned installer — see
    rem installer\README.md "If Windows Defender deletes the installer".
    certutil -hashfile "%%F" SHA256 | findstr /v "hash CertUtil"
)
endlocal
