@echo off
setlocal
rem ============================================================================
rem Builds a PORTABLE (no installer) distribution: a folder the user unzips
rem and runs directly - no Setup.exe, no elevation, no silent child-process
rem install steps. Avoids the "unsigned installer that silently launches other
rem executables" pattern that trips Windows Defender's dropper heuristics on
rem TeleRehabSetup-*.exe. Trade-off: no Start Menu shortcut / uninstaller, and
rem the user must run the (optional) VC++ redist manually, once, themselves.
rem
rem Usage:
rem   installer\build_portable.cmd                       dashboard only
rem   installer\build_portable.cmd "D:\SmartGameBuild"   bundle the Unity app
rem   installer\build_portable.cmd "" nobuild            reuse existing payload
rem ============================================================================

set "INSTALLER_DIR=%~dp0"
set "REPO_ROOT=%INSTALLER_DIR%.."
set "UNITY_BUILD=%~1"
set "SKIPBUILD="
if /i "%~1"=="nobuild" ( set "UNITY_BUILD=" & set "SKIPBUILD=1" )
if /i "%~2"=="nobuild" set "SKIPBUILD=1"
set "STAGE=%INSTALLER_DIR%portable_stage"
set "OUTDIR=%INSTALLER_DIR%Output"
set "ZIPNAME=TeleRehab-Portable-1.0.0.zip"

echo === TeleRehab portable build ===

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

rem -- 2. Stage the folder layout ------------------------------------------------
echo [2/4] staging portable folder
if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%\dashboard"
robocopy "%REPO_ROOT%\build\windows\x64\runner\Release" "%STAGE%\dashboard" /E >nul

if "%UNITY_BUILD%"=="" (
    if exist "%INSTALLER_DIR%unity_payload" (
        echo       reusing existing installer\unity_payload
        mkdir "%STAGE%\unity"
        robocopy "%INSTALLER_DIR%unity_payload" "%STAGE%\unity" /E >nul
    ) else (
        echo       no Unity build given - dashboard-only package
    )
) else (
    if not exist "%UNITY_BUILD%" ( echo ERROR: folder not found: %UNITY_BUILD% & exit /b 1 )
    mkdir "%STAGE%\unity"
    robocopy "%UNITY_BUILD%" "%STAGE%\unity" /E /XD "*_BackUpThisFolder_ButDontShipItWithYourGame" "*_BurstDebugInformation_DoNotShip" >nul
)

rem VC++ redist is included but NOT auto-run - the user double-clicks it
rem manually if Windows reports a missing runtime. No silent child-process
rem launch inside an installer = one less dropper-pattern signal.
if exist "%INSTALLER_DIR%redist\vc_redist.x64.exe" (
    copy /y "%INSTALLER_DIR%redist\vc_redist.x64.exe" "%STAGE%\" >nul
)

(
echo TeleRehab Dashboard - portable package
echo =======================================
echo.
echo No installer, no admin rights required. To run:
echo   1. If this is the first app needing it, double-click vc_redist.x64.exe once
echo      ^(only needed if Windows says a DLL/runtime is missing - most PCs already have it^)
echo   2. Open the dashboard folder and run telehealth_dashboard.exe
echo   3. The Unity capture app ^(unity\Smart Game.exe^) is auto-detected - no setup needed
echo.
echo The in-app setup guide covers requirements ^(ZED SDK, sensors^) on first launch.
) > "%STAGE%\README.txt"

rem -- 3. Zip it -----------------------------------------------------------------
echo [3/4] compressing
if not exist "%OUTDIR%" mkdir "%OUTDIR%"
if exist "%OUTDIR%\%ZIPNAME%" del /q "%OUTDIR%\%ZIPNAME%"
powershell -NoProfile -Command "Compress-Archive -Path '%STAGE%\*' -DestinationPath '%OUTDIR%\%ZIPNAME%' -CompressionLevel Optimal"
if errorlevel 1 ( echo ERROR: Compress-Archive failed & exit /b 1 )

rem -- 4. Report -------------------------------------------------------------------
echo [4/4] done
for %%F in ("%OUTDIR%\%ZIPNAME%") do (
    echo %%~nxF
    certutil -hashfile "%%F" SHA256 | findstr /v "hash CertUtil"
)
endlocal
