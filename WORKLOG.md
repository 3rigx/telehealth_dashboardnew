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