# Building the Windows installer

Produces a single `TeleRehabSetup-<version>.exe` that installs the Flutter
dashboard and (optionally) the Smart Game Unity capture app on a lab PC.

This file is for **building** the installer/portable package. For what an
**operator setting up a capture PC** needs to install (ZED SDK version,
Unicorn EEG suite, etc.), see [`INSTALL.md`](../INSTALL.md) at the repo root.

## One-time prerequisites (build machine)

| What | How |
|---|---|
| Flutter SDK | already set up on this machine |
| Inno Setup 6 | `winget install JRSoftware.InnoSetup` |
| Unity player build | `installer\build_unity.cmd` (headless batchmode build; Unity Editor must be **closed**; output → `telehealth-unity\Builds\Windows`) — or manually: Unity Editor → **File → Build Settings/Profiles → Windows (x86_64) → Build** |

## Build

```bat
:: dashboard + Unity capture app (recommended)
installer\build_installer.cmd "D:\SmartGameBuild"

:: dashboard only
installer\build_installer.cmd

:: reuse the existing Flutter payload (skip the rebuild)
installer\build_installer.cmd "" nobuild
```

The script: builds the Flutter release → copies the Unity build into
`installer\unity_payload` → downloads the VC++ runtime if missing → compiles
`telerehab.iss` → writes `installer\Output\TeleRehabSetup-<version>.exe`.

(It is a `.cmd` on purpose: this machine's Group Policy enforces `AllSigned`
for PowerShell scripts, which blocks unsigned `.ps1` files; batch files are
unaffected.)

Bump the version in `telerehab.iss` (`MyAppVersion`) and `pubspec.yaml` together
when releasing. Keep `AppId` unchanged so upgrades install over cleanly.

## What the installer does on a target PC

- Installs to `C:\Program Files\TeleRehab\` (`dashboard\` + `unity\`)
- Start-menu + optional desktop shortcut, uninstaller
- Silently installs the Microsoft VC++ runtime (needed by Flutter)
- On first launch the dashboard **auto-detects the bundled Unity player**
  (sibling `unity\` folder) — no path setup needed — and shows the in-app
  setup guide

## What it deliberately does NOT install

- **Stereolabs ZED SDK** — GPU-specific and licensed; install it from
  stereolabs.com on each capture PC (requires an NVIDIA/CUDA GPU). The
  final installer page and the in-app guide both remind the operator.

  **Tested configuration (the dev/capture rig, 2026-07-13):** ZED SDK
  **5.4.0** + CUDA **13.2** + NVIDIA driver 596.21. Match these on new capture
  PCs. The ZED SDK installer fetches its matching CUDA automatically if
  missing — no separate CUDA install needed. CUDA is only required by the ZED
  SDK; the dashboard and Unity app never use it directly (a dashboard-only /
  replay PC needs no NVIDIA GPU at all).

  **The ZED SDK version on every capture PC must match what the Unity
  project was built against** (pinned in `telehealth-unity\Packages\manifest.json`,
  `com.stereolabs.zed` git tag). A mismatch doesn't fail loudly — the native
  plugin loads but a specific function call fails ("The specified procedure
  could not be found" in `Player.log`), and the app can crash minutes later
  when that code path is actually hit. If you bump the SDK version, update the
  git tag in `manifest.json` to match (check available tags with
  `git ls-remote --tags https://github.com/stereolabs/zed-unity.git`), install
  the matching SDK on the build machine, then rebuild via `build_unity.cmd`.
  Note: Stereolabs renamed the native plugin file between releases —
  `sl_unitywrapper.dll` (SDK 5.2.x) became `sl_zed_c.dll` + `sl_zed_unity.dll`
  (SDK 5.4.x). Don't be alarmed if the old filename is "missing" after an
  upgrade; check for the new ones instead.
- Sensor drivers (FSR serial adapter, Unicorn Bluetooth dongle) — plug-and-play
  or vendor-provided.

Recorded data never lives in Program Files — sessions/protocols/exercises/
participants are written per-user under
`%USERPROFILE%\AppData\LocalLow\DefaultCompany\Smart Game\`.

## If Windows Defender deletes/quarantines the installer

Expected, not a bug in the app: `TeleRehabSetup-*.exe` is an **unsigned**
Inno Setup installer that silently launches another executable (the Unity
player) — that combination is a classic malware-dropper heuristic, so
Defender (and SmartScreen) treat it with suspicion until it earns reputation.
Every real fix that doesn't require admin rights on the target machine:

1. **On an IT-managed target machine (recommended): ask IT for a hash-based
   allow rule.** Every `build_installer.cmd` run now prints the installer's
   SHA-256 automatically (via `certutil`) — send IT that file + hash and ask
   them to add a Microsoft Defender indicator/exclusion for it (Intune:
   *Endpoint security → Antivirus → Indicators*; GPO-managed Defender: a
   path or hash exclusion policy). This requires zero admin action from you
   on the target device and doesn't weaken protection for anything else.
2. **No IT/admin reachable anywhere:** submit the exe at
   <https://www.microsoft.com/en-us/wdsi/filesubmission> as a suspected false
   positive (free; Microsoft reviews and clears it in cloud/definition
   updates, typically within 1–3 business days). Re-submit after each new
   build — the hash changes every time.
3. **Longer-term, if this will ship to many machines:** get a code-signing
   certificate and sign `TeleRehabSetup-*.exe` (and ideally the inner
   `telehealth_dashboard.exe`) — this is what removes the "unsigned, unknown
   publisher" heuristic at the source; an EV certificate gets instant
   SmartScreen trust instead of building reputation over time.

Separately: the installer currently requires **administrator rights to run**
(`PrivilegesRequired=admin` in `telerehab.iss`, because it writes to
`Program Files`). On a machine where nobody available has admin, that blocks
the install *even if Defender allows the file*. If that's also the case,
say so and the fix is a per-user variant (`PrivilegesRequired=lowest`,
installing under the user's own profile instead of Program Files) — ask for
it explicitly, since it changes where the app lives on disk.

## Portable alternative (no installer, no admin, avoids one AV trigger)

```bat
installer\build_portable.cmd "D:\SmartGameBuild"   :: with the Unity app
installer\build_portable.cmd                        :: dashboard only
installer\build_portable.cmd "" nobuild             :: reuse existing payloads
```

Produces `installer\Output\TeleRehab-Portable-<version>.zip` — a plain folder
(`dashboard\`, `unity\`, an optional `vc_redist.x64.exe` the user runs
manually, `README.txt`) instead of an installer `.exe`. No Setup wizard, no
elevation, and — importantly — **no self-extracting installer that silently
launches a second executable**, which is the specific pattern most likely to
trigger Defender's dropper heuristic on `TeleRehabSetup-*.exe`. Not a
guarantee (the individual exes are still unsigned), but a reasonable first
thing to try before code-signing or a Microsoft submission. Same
auto-detect/no-config behaviour as the installer once unzipped.

(Building it once raced Defender's own real-time scan of the freshly-copied
DLLs mid-zip — `Compress-Archive` failed with a file-in-use error. Harmless;
a retry a few seconds later succeeded. Not worth building in a retry loop for
an occasional manual build.)
