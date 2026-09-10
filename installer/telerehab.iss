; TeleRehab Dashboard — Windows installer (Inno Setup 6)
; Build with:  installer\build_installer.ps1   (or ISCC installer\telerehab.iss)
;
; Layout installed to {app}:
;   dashboard\telehealth_dashboard.exe   the Flutter dashboard (+ DLLs, data)
;   unity\<player>.exe                   the Smart Game Unity capture app
; The dashboard auto-detects the sibling unity\ player on first run, so a
; bundled install needs no manual path configuration.

#define MyAppName "TeleRehab Dashboard"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "TeleRehab Research"
#define MyAppExeName "telehealth_dashboard.exe"
#define DashboardPayload "..\build\windows\x64\runner\Release"
#define UnityPayload "unity_payload"
#define RedistFile "redist\vc_redist.x64.exe"

[Setup]
; NOTE: keep this AppId stable across releases so upgrades replace cleanly.
AppId={{8C4E19D7-52B1-4F5E-9AC1-7E3D2B6A0F44}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\TeleRehab
DefaultGroupName=TeleRehab
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=TeleRehabSetup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\dashboard\{#MyAppExeName}
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Components]
Name: "dashboard"; Description: "TeleRehab Dashboard (required)"; Types: full compact custom; Flags: fixed
#if DirExists(UnityPayload)
Name: "unity"; Description: "Smart Game capture app (Unity player)"; Types: full custom
#endif

[Files]
; ── Flutter dashboard (flutter build windows --release) ──────────────────────
Source: "{#DashboardPayload}\*"; DestDir: "{app}\dashboard"; \
  Flags: ignoreversion recursesubdirs createallsubdirs; Components: dashboard

; ── Unity capture app (copied into installer\unity_payload by the build
;    script; the section is skipped automatically when no payload exists) ─────
#if DirExists(UnityPayload)
Source: "{#UnityPayload}\*"; DestDir: "{app}\unity"; \
  Flags: ignoreversion recursesubdirs createallsubdirs; Components: unity
#endif

; ── Microsoft Visual C++ runtime (required by Flutter on clean machines) ─────
#if FileExists(RedistFile)
Source: "{#RedistFile}"; DestDir: "{tmp}"; Flags: deleteafterinstall
#endif

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\dashboard\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\dashboard\{#MyAppExeName}"; Tasks: desktopicon

[Run]
#if FileExists(RedistFile)
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; \
  StatusMsg: "Installing Microsoft Visual C++ runtime…"; Flags: waituntilterminated
#endif
Filename: "{app}\dashboard\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; \
  Flags: nowait postinstall skipifsilent

[Messages]
; Shown on the final page — the bits an installer can't do for you.
FinishedLabel=Setup has finished installing [name].%n%nBefore the first capture session, remember:%n• Install the Stereolabs ZED SDK (requires an NVIDIA GPU) for the ZED 2i camera%n• The in-app setup guide covers everything else on first launch
