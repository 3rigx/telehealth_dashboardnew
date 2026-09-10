# TeleRehab — Installation Guide

For whoever is setting up a new capture PC. Follow this **in order** — some
steps depend on the previous one. Everything here is either **Required**
(the app won't work without it) or **Optional** (only needed if that sensor
is used).

> **The single most important rule on this page:** install the **exact**
> versions listed below, not "whatever's newest." Installing a newer ZED SDK
> than the app was built for has already caused a real, hard-to-diagnose
> crash on this project (see step 3) — mismatched versions fail silently,
> not with a clear error.

---

## 0. Before you start

| Requirement | Needed for |
|---|---|
| Windows 10 or 11, 64-bit | Everything |
| Administrator rights *(only for steps 2–4 below; the app itself doesn't need admin — see step 5)* | Installing the VC++ runtime, ZED SDK, Unicorn Suite |
| ~10 GB free disk space | ZED SDK + CUDA (~6 GB) + the app + recorded sessions |
| Internet access | Downloading the installers below |

---

## 1. Microsoft Visual C++ Redistributable — **Required**

The dashboard (built with Flutter) needs this to run at all.

- If you're using **`TeleRehabSetup-*.exe`**, this installs automatically — skip this step.
- If you're using the **portable ZIP** (`TeleRehab-Portable-*.zip`), double-click `vc_redist.x64.exe` inside the extracted folder once. Harmless to run even if already installed.

## 2. Stereolabs ZED SDK — **Required for motion capture (ZED 2i camera)**

- **Version: 5.4.0 exactly.** Install from Stereolabs' official downloads
  page. If 5.4.0 isn't the version offered by default, look for a
  "previous releases" / archive section — do not install whatever is newest
  without checking it matches this number first.
- Requires an **NVIDIA GPU with CUDA support**. The ZED SDK installer pulls
  down the matching CUDA toolkit automatically — you don't need to install
  CUDA separately.
- **Tested working combination** (this project's dev/capture rig): ZED SDK
  **5.4.0** + CUDA **13.2** + a recent NVIDIA driver. If your GPU driver is
  very old, update it first via NVIDIA's site or Windows Update.
- A PC that will only be used for **replaying/reviewing already-recorded
  sessions** (not live capture) doesn't need a GPU or the ZED SDK at all.

**Why the version has to match exactly:** the Unity capture app is built
against a specific version of Stereolabs' Unity plugin, which is tied to a
specific SDK version. A mismatch doesn't fail with an obvious error — the
native plugin loads, but a function call inside it silently fails
("The specified procedure could not be found" in the log), and the app can
run for a while and then crash mid-session. If a different SDK version is
ever required going forward, the whole project needs rebuilding to match —
that's a developer task, not something to work around by installing
"whatever's close enough."

## 3. ZED 2i camera — **Required for motion capture**

- Plug into a **USB 3.0** port (blue connector) — USB 2.0 is not enough
  bandwidth for the camera stream.
- Position it so the participant's **whole body** stays in view,
  roughly **2–4 metres** away.

## 4. Unicorn Hybrid Black EEG headset — **Optional**

Only needed if a session will record EEG.

- Install **Unicorn Suite Hybrid Black** (get it from g.tec's official
  site). This provides the Bluetooth dongle driver and the Unicorn Recorder
  app, which is useful for verifying the headset pairs correctly before
  relying on it in a session.
- **Use the g.tec CSR Bluetooth dongle that ships with the headset** — do
  **not** pair the headset over a laptop's built-in Bluetooth. The built-in
  radio is explicitly flagged as "not recommended" by g.tec and causes
  connection timeouts in practice on this project.
- Windows only runs one Bluetooth stack at a time. If the CSR dongle fails
  to install (Device Manager shows a driver error), **disable the PC's
  built-in Bluetooth radio** in Device Manager, then reconnect the dongle.
- After pairing, note which **COM port** Windows assigns the headset —
  re-pairing can change it. The dashboard's Settings screen lets you set
  the EEG COM port if it isn't the default.

## 5. The TeleRehab app itself — **Required**

Two ways to install — use whichever one you were given:

- **`TeleRehabSetup-<version>.exe`** — a normal installer. Requires admin
  rights on the target PC. Installs the dashboard, the Unity capture app,
  Start Menu shortcuts, and an uninstaller.
- **`TeleRehab-Portable-<version>.zip`** — no installer, no admin rights.
  Unzip anywhere and run `dashboard\telehealth_dashboard.exe` directly. Keep
  the `dashboard\` and `unity\` folders **together, as siblings** — the app
  auto-detects the bundled capture app from its own location and moving one
  folder away from the other breaks that.

  If the zip was downloaded (not copied from USB/network share) and
  something in it won't run, right-click the `.zip` → Properties → **Unblock**
  → Apply, *then* extract it — Windows tags downloaded files in a way that
  can interfere with running the programs inside.

Either way, the dashboard's **Unity Engine** setting in Settings should
already point at the bundled capture app — no manual path setup needed.

## 6. FSR pressure insoles — **Optional**

Only needed if a session will record plantar pressure. Connects over either:
- **USB** (appears as a COM port — pick it in Settings → FSR Pressure Insole)
- **Wi-Fi** (WebSocket/TCP — enter the device's address in Settings)

No separate driver install is normally required.

---

## First launch

Open the dashboard — it walks through a short **setup guide** automatically
the first time (also reachable any time via **Settings → Help → Show setup
guide**), covering the day-to-day workflow: enrolling a participant,
designing a protocol, and running a live session.

## If something doesn't start

1. **Live Exercise / Run live does nothing:** check the dashboard's Unity
   connection status on the home screen (top-right). It should say
   *Connected*; the app launches the capture app itself if it isn't already
   running.
2. **The capture app appears in Task Manager then disappears:** almost
   always a native plugin problem — see Unity's own log at
   `%USERPROFILE%\AppData\LocalLow\DefaultCompany\Smart Game\Player.log`.
   Search it for "error", "exception", or "Failed to load". A ZED SDK
   version mismatch (step 2) is the most common cause.
3. **Windows Defender/SmartScreen flags the installer or capture app:**
   expected for unsigned software from a small research project, not a sign
   anything is actually wrong. See `installer/README.md` in the source
   repository for the no-admin ways to resolve it (Microsoft false-positive
   submission, the portable ZIP, or code-signing).

Recorded data is never stored inside the app's install folder — it lives
per-user under `%USERPROFILE%\AppData\LocalLow\DefaultCompany\Smart Game\`.

## After installing: confirm the sensors are actually accurate

Installing and connecting a sensor isn't the same as it reporting correct
data. Before trusting any recorded session — and after any hardware or SDK
change — run through **[`VALIDATION.md`](VALIDATION.md)**, a checklist of
physical tests (an EEG eyes-closed test, a ZED goniometer check, etc.) that
confirm the data is right, not just present.
