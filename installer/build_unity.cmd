@echo off
setlocal
rem ============================================================================
rem Builds the Smart Game Unity player headlessly (batchmode).
rem
rem Usage:  installer\build_unity.cmd
rem Output: C:\UnityProjects\telehealth-unity\Builds\Windows\Smart Game.exe
rem
rem Requirements:
rem   - the Unity EDITOR must be CLOSED (a project can only be open once)
rem   - takes ~5 minutes; progress is written to Builds\build.log
rem After this, bundle it into the installer with:
rem   installer\build_installer.cmd "C:\UnityProjects\telehealth-unity\Builds\Windows"
rem ============================================================================

set "UNITY_EXE=C:\Program Files\Unity\Hub\Editor\6000.4.0f1\Editor\Unity.exe"
set "PROJECT=C:\UnityProjects\telehealth-unity"
set "OUT=%PROJECT%\Builds\Windows\Smart Game.exe"

if not exist "%UNITY_EXE%" (
    echo ERROR: Unity 6000.4.0f1 not found at "%UNITY_EXE%" - adjust UNITY_EXE in this script.
    exit /b 1
)
tasklist /FI "IMAGENAME eq Unity.exe" /NH | find /i "Unity.exe" >nul
if not errorlevel 1 (
    echo ERROR: the Unity Editor is running - close it first ^(the project can only be open once^).
    exit /b 1
)

echo Building Smart Game player (about 5 minutes, log: %PROJECT%\Builds\build.log) ...
"%UNITY_EXE%" -batchmode -quit -projectPath "%PROJECT%" ^
    -buildWindows64Player "%OUT%" -logFile "%PROJECT%\Builds\build.log"

if not exist "%OUT%" (
    echo ERROR: build finished but "%OUT%" is missing - check the log ^(or antivirus quarantine^).
    exit /b 1
)
echo DONE - %OUT%
endlocal
