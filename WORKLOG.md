# TeleRehab Dashboard — Work Log

Running log of work done and changes made. **Newest entries are appended at the bottom of the Change Log.**
Entry format:

```
### YYYY-MM-DD  HH:MM
**DO:**  <what was changed / done>
**Why:** <the reason / intent>
```

> Times for entries before 2026-07-02 are approximate (reconstructed; precise timestamps
> weren't recorded at the time). Entries from 2026-07-02 onward use real timestamps.

---

## Pending / Recommended fixes (prioritized)

Derived from the 2026-07-02 critical review.

**P0 — data integrity / scientific validity** ✅ DONE 2026-07-02 (Change Log 14:06)
- ~~Measure Flutter↔Unity latency & correct marker times.~~ Ping/pong handshake added; offset measured & stored in `run.json`; marker `t_ms` corrected onto Unity's record clock (raw kept as `t_run_ms`). **Needs one live run to confirm the measured offset is sane.**
- ~~Recompute reps from the recorded file.~~ Reps recomputed from `zed_skeleton.json` per active window; canonical value in `run.json` (`repsSource` / `liveReps` / `repsByBlock`).
- ~~Persist markers incrementally.~~ Markers appended (sync + flush) to `_pending/…/markers.partial.csv` as they fire; reconciled into the session folder on save.
- ~~Calibrate the EEG µV scale.~~ Scale made runtime-overridable (PlayerPrefs `EegScaleUv`) + calibration procedure documented in-code. **The numeric calibration still needs a paired headset+Recorder capture to finalise.**

**P1 — reliability**
- ~~Pre-flight signal-quality gate before Begin~~ ✅ DONE 2026-07-02 14:21 (Change Log) — EEG-railed / FSR-zero / skeleton-tracked check gates Begin, with an operator override.
- **Write absolute timestamps from Unity** and drop the delta + `cumulativeTimeline` heuristic in `session_repository.dart`.
- **Persist dropped-frame counts** (EEG `FramesDropped`, and skeleton/FSR gaps) into the manifest so analysis sees gaps.
- **Add tests**: EEG decode (known frame→µV), sequence generator (even split / no-repeat / counterbalance counts), timeline reconstruction, CSV parsers, rep detector.

**P2 — product / research value**
- **Auto-epoched, analysis-ready export** (per-condition long-format CSV / EDF) instead of raw zips.
- **Study-level counterbalance manager** (Latin-square group assignment across the participant pool) — current per-run random seed doesn't balance the group.
- **Trial annotation + exclude flag** ("participant sneezed at block 7").
- **Aggregate analysis** across the protocol's own block structure (condition A vs B).

---

## Change Log

### 2026-06-18 → 2026-06-19  (time approx)
**DO:** Built the license-free Unicorn Hybrid Black **EEG capture pipeline** — `UnicornEegConnector` (bg-thread raw-SPP decode, counter-locked framing) + `UnicornEegProbe`, `EegRecorder`, `EegBandPower` (Goertzel θ/α/β), `EegCsvWriter`→`eeg.csv`; wired into `ExerciseController` gated by `SessionContext.EegEnabled`; broadcaster emits an `eeg` object; Flutter `EegData` + `eeg_panel`/fusion + replay loader. Confirmed the 45-byte frame layout (2 header + 8×3 EEG 24-bit **big-endian** + accel + gyro + battery + uint32 LE counter + `0D 0A`) byte-by-byte against a real capture.
**Why:** Add EEG as a third modality without a g.tec licence (`UnicornSuite.lic` was empty) by reverse-engineering the raw Bluetooth-SPP protocol.

### 2026-06-22  (time approx)
**DO:** Validated the headset in **Unicorn Recorder** — clean channels + a clear eyes-closed **alpha** rise on the occipital channels. Established that the unworn bench/touch test is inherently ambiguous (open electrodes rail); the decode itself is correct.
**Why:** Prove the hardware + our decode read genuine EEG before trusting the pipeline.

### 2026-06-25  (time approx)
**DO:** Locked Protocol Builder decisions (one continuous recording + block markers; single-window participant toggle; per-class exercise/feedback; permuted-blocks counterbalance; ≈6-min editable timing). Built **Phase 1** — `models/protocol.dart`, `services/protocol_repository.dart` (JSON persistence), `screens/protocol/protocol_builder_screen.dart`, nav card + `/protocols` route, `AppSettings.protocolsRoot`.
**Why:** Turn ad-hoc capture sessions into a reusable, research-grade experiment designer.

### 2026-06-26  (time approx)
**DO:** **Phase 2** — `protocol_runner.dart` (clock/sequencing + knee-angle rep detector), `participant_screen.dart` (phased full-screen run view + feedback widgets), `widgets/eeg_channel_map.dart`. **Phase 3** — `protocol_run_controller.dart` (live run: connect→configure→start_session→Begin→`start_recording`→`stop_recording`; writes `markers.csv`/`protocol.json`/`run.json` on `session_saved`); "Run Live" entry. **Phase 4** — marker parsing + replay block-timeline overlay + `.zip` export (`archive` pkg). Moved block timing **onto each class** (`ProtocolClass`). Added warm-up detection (`UnityConnectionService.receivingLive`) + `SensorWarmupLoader` gating the live monitor and Run Live "Begin". Made the **back button / dispose stop Unity recording** on the live monitor and participant screens. Run Live now force-disables dashboard mocks (live = real data).
**Why:** Complete the builder end-to-end; make sensor warm-up an explicit visible state; never leave Unity recording orphaned; ensure a "live" run shows real sensors, not mock overlay.

### 2026-06-29  (time approx)
**DO:** Restyled the whole app to the **Daydream design system** — new `AppColors` palette (Peach/Sky/Ink/Paper + pastels + Violet interactive), `AppRadius`/`AppSpace`, Schibsted Grotesk text theme + Caveat eyebrows; swapped Inter→Schibsted Grotesk app-wide; **light "chrome"** (Home/Builder/Settings) + **dark "Ink" data screens** (live monitor/replay/participant) using `ink*` tokens; global **pill buttons** via theme; per-screen editorial polish. Added a **runtime light/dark toggle** (mode-aware semantic tokens, persisted `AppSettings.darkMode`, sun/moon button in the Home rail). Added the **active-phase exercise-guide GIF** panel, **runtime hide toggles for the FSR/EEG panels** in the participant control strip, and a **gamified rep counter** (`_RepGauge`: progress ring per 5 reps, pop animation, flame streak, milestone cheers).
**Why:** Adopt the provided brand/design system; give day/night flexibility; let the participant follow the exercise guide during the block; let the operator declutter the run view; motivate the participant.

### 2026-07-02  09:50
**DO:** Delivered a critical system review (clock desync between Flutter markers and Unity data; uncalibrated EEG µV; cross-modal alignment risk; reps computed from the live/mock stream; markers as a single point of failure; per-run vs study-level counterbalancing; no tests). Created this `WORKLOG.md` and backfilled the change log, plus the prioritized fix backlog above.
**Why:** User asked for an honest, critical assessment and a maintained task log (date / time / DO / Why).

### 2026-07-02  14:06
**DO:** Implemented all four **P0 data-integrity fixes**.
- **Reps from the recorded file** — new `lib/services/rep_analysis.dart`: shared `KneeRepCounter` (single source of truth for the hysteresis, now used by both the live runner and the recompute), `kneeFlexionDeg` (from hip→knee→ankle joints), and `recomputeRepsFromRecording` (parses `zed_skeleton.json`, rebuilds the timeline via the now-public `cumulativeTimeline`, counts reps per active window). `ProtocolRunController._writeArtifacts` recomputes and writes canonical `reps` + `repsSource`/`liveReps`/`repsByBlock` into `run.json`. `ProtocolRunner` refactored to use the shared counter.
- **Incremental markers** — `ProtocolRunner.onMarker` callback fires as each marker is logged; the controller appends it (sync + flush) to `<protocolsRoot>/_pending/<pid>_<ts>/markers.partial.csv` with a `run.partial.json` sidecar, and reconciles/cleans it into the session folder on save. Crash mid-run no longer orphans the block structure.
- **Clock offset** — Flutter sends 5 `ping`s at run start, keeps the lowest-RTT `pong`, computes `clockOffsetMs = (sentAt + rtt/2) − unityRecMs`; Unity (`TelerehabBroadcaster.RecordingClockMs` + a `ping`→`pong` case in `TelerehabWebSocketServer`) echoes its record-clock ms on the main thread. `markers.csv` now writes corrected `t_ms` (+ raw `t_run_ms`), and `run.json` records `clockOffsetMs`/`clockRttMs`/`markerTimebase`. Degrades gracefully to the raw run clock if Unity doesn't answer.
- **EEG scale** — `UnicornEegConnector.EegScaleUv` is now a runtime-settable field seeded from PlayerPrefs `EegScaleUv` (default = derived `DefaultScaleUv`), with the full calibration procedure documented in-code.
**Why:** Make the recorded data trustworthy for research — reps reflect saved data not the lossy/mock display; block markers survive a crash; markers align to the sensor timeline; absolute EEG µV can be calibrated without a recompile.
**Verify:** `flutter analyze` clean on all changed Dart (0 new issues; 15 pre-existing info lints elsewhere). Unity C# is additive (static property, one DTO field + `case`, one static field) but the MCP bridge was revoked so it wasn't validated through Unity — needs a normal Editor recompile + one live run to confirm the pong offset and the recorded-rep count.

### 2026-07-02  14:21
**DO:** Added the **P1 pre-flight signal-quality gate**. New `lib/services/signal_quality.dart` (`assessSignalQuality` → `SignalReport` of per-sensor `SignalLevel` ok/warn/bad, only for the sensors the protocol enables): ZED = a body with ≥8 tracked joints; FSR = non-zero load (catches the wrong-COM-port all-zeros case); EEG = ≥6/8 channels within [0.5, 5000] µV RMS (railed = open electrode, flat = dead). `ProtocolRunController` exposes `signalReport` + `canBegin` (warm-up done AND signals pass, unless overridden) + `overrideQualityGate`/`setOverrideGate`. The participant `_beginOverlay` now shows a live per-sensor checklist, disables **Begin** until green, and offers a "Start anyway — I've checked the sensors" override (button then reads "Begin anyway").
**Why:** Stop wasting whole sessions on a mis-connected sensor — the FSR-zero (wrong port) and unworn-EEG (railed) failures we already hit are now visible and blocking *before* recording starts, while still letting the operator proceed deliberately.
**Verify:** `flutter analyze` clean on the 3 changed/added files (0 new issues). Pure `assessSignalQuality` is unit-testable; live checklist refreshes on each `sensor_update` (screen already rebuilds on the connection listener).

### 2026-07-03  08:46
**DO:** Fixed a Unity bug that blocked ZED-only capture (surfaced testing the P0 work with just the ZED 2i). `SensorSystemController.Start()` (Unity C#) always created + opened the FSR serial port regardless of `SessionContext.FsrEnabled`, and `FsrConnector.Connect()` was unguarded — with no FSR plugged in it threw `IOException: The port 'COM3' does not exist.`, aborting `Start()` so `_fsrController` stayed null and `Read()`/`GetState()` then NPE'd every frame, taking the ZED capture down with it. Now: (1) skip FSR entirely when `SessionContext.FsrEnabled` is false; (2) wrap the connect so a hardware/port failure logs a warning and continues *without* FSR instead of aborting; (3) null-guard `Read()` and emit empty `FSRState` from `GetState()` when there's no FSR. `SessionWriter` already gates `fsr.csv` on `FsrEnabled`, so a ZED-only run writes no bogus FSR data.
**Why:** Let a camera-only protocol (FSR/EEG disabled) actually run, and make the sensor system robust to any one sensor failing to connect (the ZED should never die because an insole is unplugged).
**Verify:** Not validated through Unity (MCP bridge still revoked) — needs an Editor recompile. Change is small/scoped: gate on the existing `SessionContext.FsrEnabled`, catch around `Connect()`, `_fsrController?.` + empty `FSRState` fallback (types confirmed: `CombinedFSRController.GetState()`→`(FSRState,FSRState)`, `FSRState()` no-arg ctor). Expect the COM3 error gone and the ZED to start for a ZED-only run.
**Result:** ✅ ZED-only run succeeded (session `treyuyy59/2026-07-03_08-53-34_Idle`). P0 pipeline confirmed end-to-end: `repsSource="recorded_skeleton"`, `reps=33` (per-block breakdown correct — REST blocks 0, MOVE/MOVE+COUNT 3–5 each), `markers.csv` has the 7-col schema + `t_run_ms`, `markerTimebase="unity_record_clock"`. Two findings → next entry.

### 2026-07-03  10:01
**DO:** Two fixes from the first live ZED-only run's data.
- **Live rep counter was counting 0 on real data** (`run.json liveReps=0` vs recomputed `reps=33`). Root cause: the live path read the `jointAngles` stream, which is the *interior* knee angle (180°=straight), but the hysteresis thresholds expect *flexion* (0°=straight) — so it never tripped. Changed `ProtocolRunner._kneeAngle` to compute `kneeFlexionDeg(skeleton)` (the same geometry the recorded recompute uses), so the live gamified count is correct and matches the saved value. (This run also *validated* Fix #1: recompute recovered 33 where the live count would have saved 0.)
- **Clock offset was noisy/over-measured** (`clockOffsetMs=1008`, `clockRttMs=455` → first marker `t_ms=-1008`). The 5 pings at 150 ms all landed in the busy window right after recording start (scene + first frames saturate Unity's main thread), inflating RTT and biasing the offset. Changed `_startClockSync` to ping every 400 ms for up to ~12 s (30 pings) keeping the lowest-RTT reply, stopping early once a clean (<15 ms) round trip lands — so the offset is measured during a quiet moment and is trustworthy.
**Why:** Make the participant-facing count correct (not just the saved file), and get an accurate clock offset instead of one biased by main-thread contention.
**Verify:** `flutter analyze` clean on both changed files. Needs a re-run to confirm: `liveReps` should now ≈ `reps`, and `clockOffsetMs` should drop to a low/steady value (if it stays ~1 s with a clean <15 ms RTT, that's a genuine start_recording→record-clock latency to address at the source next).

### 2026-07-03  12:05
**DO:** **Phase 1 of the generalized rep engine** (see memory [[rep-counting-and-authoring]]). Replaced the single hardwired knee detector with a person-calibrated, joint-agnostic engine. New `lib/services/motion_rep.dart`: `channelAngle` (interior flexion of knee/elbow/shoulder/hip × L/R from joint positions); `CyclicRepDetector` — counts oscillations relative to the individual's OWN observed range (Schmitt trigger at 70%/30% of range, mean≈rest, `minRangeDeg=12` noise floor, `debounceMs=350`), so limited ROM still counts (rep = effort, not achievement); `analyzeBlockReps` runs a detector per channel, merges events across channels within `mergeMs=300` (one physical movement / synchronized limbs = 1 rep; alternating limbs = separate) and reports the dominant joint; `LiveRepEngine` = the same logic online. `rep_analysis.dart` recompute now uses `analyzeBlockReps` and returns per-rep events + dominant joint per block. `protocol_runner` live path swapped to `LiveRepEngine` (feeds the whole skeleton). `run.json` gains `repJointByBlock` + `repEvents` (per-rep timestamps, for audit). Removed `KneeRepCounter`/`kneeFlexionDeg`.
**Why:** Fix "only one leg counts" (it was locked to `kneeR`, which renders as the participant's left leg) and make the counter work for ANY exercise and any tracked limb — the foundation the authoring flow (Phase 2) reuses to derive a movement's signature. Person-calibration is the equity fix: no absolute angle bar that would penalise limited-ROM users.
**Verify:** `flutter analyze` clean on all 4 changed files; no remaining refs to the removed detector. Needs a ZED-only re-run to confirm: raising EITHER leg (or an arm) now counts; `run.json` should show `repJointByBlock` (e.g. "knee") + a `repEvents` list whose per-block counts match `repsByBlock`. Tunables (`minRangeDeg`/`mergeMs`/`debounceMs`) may need adjusting against real footage.
**SUPERSEDED same day — see 12:27.**

### 2026-07-03  12:27
**DO:** **Removed the rep counter / score entirely** (reverses the 12:05 Phase 1 work). Per the user: a completion score is subjective and inequitable — it assumes everyone can complete the movement, penalising limited-ROM/disabled participants — so counting is dropped, not made person-relative. Deleted `motion_rep.dart` + `rep_analysis.dart`; stripped `reps`/`_repsAccum`/`totalReps`/`feedSensor`/`activeWindowsFromMarkers` from `ProtocolRunner`; removed the rep recompute + all rep fields (`reps`/`totalReps`/`repsSource`/`liveReps`/`repsByBlock`/`repJointByBlock`/`repEvents`) from `run.json` in `protocol_run_controller`; removed `_RepGauge` + `_repCard` + the "total reps" stat + the `feedSensor` call from `participant_screen`; removed `ClassFeedback.repCounter` (model + `toJson`/`fromJson`) and the "Repetition Counter" builder toggle + template defaults. The raw skeleton is still recorded; the app simply never counts/scores reps. `run.json` keeps sequence + clock-alignment; `markers.csv` unchanged.
**Why:** User: "remove the count/rep score because it's subjective to the fact everyone can complete the exercise." Equity-first — no success metric that a participant can "fail".
**Note:** A SEPARATE, older single-session **replay analytics** rep detector still exists (`replay_engine._detectReps` → `replay_screen` "Repetitions" + ROM charts). Flagged to the user; left in place pending their decision (it also carries descriptive ROM data).
**Verify:** `flutter analyze` clean (0 errors; the usual 15 pre-existing info lints). Next: build the **Exercise authoring** section (record a movement via ZED → native skeleton-avatar guide, selectable in the protocol builder) — see memory [[rep-counting-and-authoring]].

### 2026-07-03  12:40
**DO:** **Exercise authoring — Increment 1 (library foundation).** New `Exercises` section: `models/exercise_asset.dart` (`ExerciseAsset` — recorded avatar clip or uploaded media, stored per-folder), `services/exercise_repository.dart` (`<exercisesRoot>/<id>/exercise.json` + `skeleton.json`; `importFromSkeletonJson`, `loadFrames` reusing `skeletonFromUnityJson`+`cumulativeTimeline`, save/delete), `widgets/avatar_guide_player.dart` (loops recorded skeleton frames on the existing `Skeleton3DView` bone avatar at the clip's own rate), `screens/exercises/exercise_library_screen.dart` (grid of exercises, preview dialog with the looping avatar, delete, "New from recording" = pick a `zed_skeleton.json` → name → import). Added `AppSettings.exercisesRoot` (+ default `…/Exercises`), the `ExerciseRepository` provider + `/exercises` route in `main.dart`, and an "Exercises" nav card in the Home rail.
**Why:** Stand up the authoring library so exercises become reusable avatar guides. Import-from-recording works TODAY with any existing `zed_skeleton.json` (e.g. the treyuyy59 session) — no Unity change — proving the model + avatar playback before building live capture.
**Verify:** `flutter analyze` clean (0 errors; usual 15 info lints). Test: Home → Exercises → New from recording → pick a session's `zed_skeleton.json` → name it → Preview should loop the movement on the avatar. Next: Increment 2 = record directly via the ZED (reuse the capture pipeline); Increment 3 = pick an exercise per class in the builder + play it as the participant's block guide.

### 2026-07-03  12:44
**DO:** **Exercise authoring — Increment 2 (record with the ZED).** `services/exercise_record_controller.dart` — `ExerciseRecordController` reuses the capture pipeline for a ZED-only authoring recording (mocks off; configure `patientId:_exercises`, zed on / fsr+eeg off → never touches COM3; start_session → warm-up gate on `receivingLive` w/ 25 s fallback → start_recording → stop_recording → on `session_saved` calls `ExerciseRepository.importFromSkeletonJson` on the session's `zed_skeleton.json`; errors if 0 frames). `screens/exercises/exercise_record_screen.dart` — dark full-screen flow: warm-up loader → live `Skeleton3DView` preview + **Record** (red) → recording w/ pulsing dot + elapsed timer + **Stop & save** (green) → saving → done ("Back to library") / error. Library header + empty state now offer **Record with ZED** (primary) alongside **Import** (a `zed_skeleton.json` file); `_recordNew` prompts a name then pushes the record screen.
**Why:** The core of the feature — a clinician demonstrates a movement once and it becomes a reusable avatar guide, no filming/GIF needed.
**Verify:** `flutter analyze` clean on the 3 changed/new files (0 issues). Needs Unity running + the ZED to test live (recording reuses the same warm-up/`session_saved` path already validated). Next: Increment 3 — builder picker (`ProtocolClass.exerciseId`) + participant block guide plays the avatar via `AvatarGuidePlayer`.