# TeleRehab — Performance Testing Guide

How to measure whether this application is fast and stable enough. It is a
**single-user, real-time capture app** (a Flutter desktop dashboard + a Unity
capture engine talking over a local WebSocket), so the meaningful questions are
**latency, throughput, jitter, and endurance** — not multi-user server load. A
tool like LoadRunner has no server here to load; these three stages measure what
actually matters instead.

Tools live in [`tool/`](tool/):
- **`tool/ws_perf_test.dart`** — synthetic dashboard client that measures the
  Unity WebSocket bridge (throughput / jitter / command latency / payload size).
- **`tool/sample_resources.ps1`** — samples dashboard + Unity CPU% and memory to
  a CSV (for the UI and soak stages).

Results (CSV) are written to the current directory by default. Keep them with a
run label so the numbers are comparable across changes.

---

## Prerequisites

- **Dart** on PATH (bundled with Flutter): `dart --version`.
- Decide **build vs editor** for Unity. A **build** (`Builds/Windows/Smart Game.exe`)
  is the realistic target; the **editor** adds profiler overhead and its process
  is `Unity`, not `Smart Game`. Prefer a build for headline numbers.
- Process names for the sampler: dashboard = `telehealth_dashboard`,
  Unity build = `Smart Game`, Unity editor = `Unity`.
- **The WebSocket harness needs no hardware.** Unity broadcasts `sensor_update`
  during *preview* (before recording), even with no camera/EEG — so `--drive`
  gives a full-rate stream on any machine.

> **Note on the PowerShell script (`.ps1`).** This machine enforces `AllSigned`
> via group policy, so the `.ps1` will **not** run via `-File`. Run it as a
> scriptblock instead (interactive code is not subject to the policy):
> ```powershell
> $sb = [scriptblock]::Create((Get-Content -Raw 'tool/sample_resources.ps1'))
> & $sb -Seconds 1800
> ```
> The Dart harness has no such restriction — run it normally with `dart run`.

---

## Stage 1 — Data-pipeline throughput & latency  *(highest value)*

Measures the real-time bridge: how fast Unity broadcasts sensor frames, how
evenly (jitter/stalls), how quickly it answers a command (ping→pong RTT), and
how big each frame is. This is the honest replacement for a "load test".

### Run it

Pick one of:

```powershell
# A) Driven — no hardware, no files. Unity streams at preview rate.
dart run tool/ws_perf_test.dart --drive --seconds 120

# B) Passive — you start a real session from the dashboard first, then measure.
dart run tool/ws_perf_test.dart --seconds 120

# C) Fan-out load — 5 concurrent dashboard clients on the one bridge.
dart run tool/ws_perf_test.dart --drive --clients 5 --seconds 120
```

For A/C, Unity must be running with the bridge up (its log shows
`[TelerehabWS] Server started on ws://localhost:8765`) and **not** also being
driven by the real dashboard at the same time (one driver only).

> **Drive from the menu; measure a running session passively.** `--drive` sends
> `configure_session + start_session`, which loads the capture scene. Start it
> with Unity sitting at the **menu**. Re-driving while Unity is *already* in a
> capture scene reloads it and re-inits the sensors — and repeated re-drives
> without a camera attached can hang ZED init (observed: the "previewing anyway"
> fallback stops firing). To measure a session that's already streaming, use
> **passive** mode (no `--drive`) instead, which is also how you get a clean
> fan-out measurement (`--clients N` without `--drive`).

### What you get

A per-second CSV (`perf_<timestamp>.csv`) and a printed summary:

| Metric | Meaning | What "good" looks like |
|---|---|---|
| **Broadcast rate (Hz)** | `sensor_update` frames/sec at the measured client | Sits at Unity's configured rate (`1 / _updateInterval`) and stays there |
| **Inter-arrival p95 / max (ms)** | Frame spacing / worst stall | p95 near the nominal frame period; no large isolated max-gaps |
| **Command RTT (ms)** | ping→pong round trip | Single-digit to low-tens on localhost; stable |
| **Payload size (bytes)** | mean `sensor_update` size | Informational — watch it doesn't balloon unexpectedly |
| **Warm-up (ms)** | time to first frame after driving | Informational (scene load) |

### How to read it

- **Rate sags below nominal** → Unity can't keep up (main-thread cost, GC, a slow
  sensor). Cross-check with the Unity Profiler (below).
- **Rising p95 / big max-gaps** → stalls: GC spikes, a blocking call, or fan-out
  cost. Re-run with `--clients 1` vs `--clients 5` to isolate fan-out.
- **RTT climbs under `--clients N`** → the broadcast fan-out is contending with
  command handling.

---

## Stage 2 — Dashboard UI smoothness

The live monitor + 3D avatar re-render on every `sensor_update`. This checks the
Flutter app renders without jank. **No Unity or hardware needed** — use the
dashboard-side mocks so the UI animates from synthetic data.

### Run it

1. Launch the app in **profile mode** (release-like, but profiler attaches):
   ```powershell
   flutter run -d windows --profile
   ```
2. In the app: **Settings → Mock data** → turn on *Mock motion*, *Mock FSR*,
   *Mock EEG*. Open the live monitor so the avatar + panels animate.
3. Open **DevTools** (the URL is printed in the `flutter run` console) →
   **Performance** tab.
4. Record ~30–60 s while interacting (switch avatar style, open replay, etc.).

### What to look for

- **Frame chart**: bars under the **16 ms** line = smooth 60 fps. Bars spiking
  over 16 ms (red) = jank — click one to see whether it's **UI** (Dart build) or
  **Raster** (GPU/paint) cost.
- **Common culprits**: rebuilding the whole tree on every frame, the 3D avatar
  paint (`Skeleton3DView`), or unbounded history lists.
- **Memory** tab: take a snapshot, interact for a few minutes, snapshot again —
  the heap should return to a baseline, not climb monotonically.

Also run the **resource sampler** in parallel to capture process CPU/RAM:
```powershell
$sb = [scriptblock]::Create((Get-Content -Raw 'tool/sample_resources.ps1'))
& $sb -Names 'telehealth_dashboard' -Seconds 120
```

---

## Stage 3 — Endurance / soak

Real research sessions run for many minutes. A short test never reveals slow
leaks or drift. Run a long session and watch memory, broadcast rate, dropped EEG
frames, and session-file growth.

### Run it

Three things at once, for e.g. 30 minutes:

1. **Drive + record** a long session (exercises the full pipeline incl. file I/O):
   ```powershell
   dart run tool/ws_perf_test.dart --drive --record --seconds 1800 --patient SOAK-TEST
   ```
   Use a throwaway `--patient` id — this writes a real session folder. Delete it
   afterwards.
2. **Sample resources** for the same duration (new terminal):
   ```powershell
   $sb = [scriptblock]::Create((Get-Content -Raw 'tool/sample_resources.ps1'))
   & $sb -Seconds 1800
   ```
3. Let it run untouched.

### What to check afterwards

- **`resources_*.csv`**: chart `working_set_mb` over time per process. A line that
  climbs and **never settles** across 30 min = a leak. A sawtooth that returns to
  baseline is normal GC.
- **`perf_*.csv`**: the broadcast `rate_hz` should be flat start-to-finish. A slow
  decline = degradation under sustained load.
- **EEG dropped frames** (only if a real headset was connected): these are
  internal to Unity and **not broadcast**, so read them from `Player.log`
  (`[EEG] …`) and from gaps in the saved `eeg.csv` sample counter — not from the
  harness.
- **Session file**: the written session folder size should track duration
  linearly (no runaway growth).

---

## Unity engine profiling (companion to Stage 1)

When Stage 1 shows a rate sag or stalls, find the cause on the Unity side:

1. Open the project in the Unity Editor → **Window → Analysis → Profiler**.
2. Enter Play mode, run a session, watch:
   - **CPU Usage**: per-frame time; spikes that exceed the frame budget line up
     with the harness's max-gaps.
   - **GC Alloc / GC.Collect**: allocation spikes cause the stalls; the
     `sensor_update` JSON `StringBuilder` and per-frame arrays are the places to
     look.
   - The **`UnicornEeg`** background thread (EEG decode) should not stall the main
     thread.
3. For build-accurate numbers, use **Development Build + Autoconnect Profiler**
   instead of the editor.

---

## Suggested acceptance targets

These are sane starting bars for a localhost single-user rig — tune to your own
observed baseline, then treat regressions against it as the real signal:

| Aspect | Target |
|---|---|
| Broadcast rate | Holds at nominal (`1 / _updateInterval`), <5% sag under `--clients 3` |
| Inter-arrival p95 | Within ~1.5× the nominal frame period |
| Worst stall (max gap) | No repeated gaps > ~3× the frame period |
| Command RTT | Median comfortably < 30 ms on localhost |
| UI frames | Vast majority < 16 ms; no sustained jank while interacting |
| Memory over 30 min | Returns to a stable baseline; no monotonic climb |

---

## Quick reference

```powershell
# Stage 1 — pipeline (no hardware)
dart run tool/ws_perf_test.dart --drive --seconds 120
dart run tool/ws_perf_test.dart --drive --clients 5 --seconds 120   # fan-out load

# Stage 2 — UI (mocks on in Settings)
flutter run -d windows --profile          # then DevTools → Performance

# Stage 3 — soak (writes a throwaway session)
dart run tool/ws_perf_test.dart --drive --record --seconds 1800 --patient SOAK-TEST

# Resource sampler (AllSigned-safe invocation)
$sb = [scriptblock]::Create((Get-Content -Raw 'tool/sample_resources.ps1')); & $sb -Seconds 1800
```
