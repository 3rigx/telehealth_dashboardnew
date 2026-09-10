# Sensor Data Validation Protocol

A checklist of tests to confirm the EEG and ZED 2i motion data are actually
correct, not just "streaming." Run this:

- **Before starting a new study or participant cohort**
- **After any hardware change** — new headset/dongle, new capture PC, a ZED
  SDK upgrade (a version mismatch has already caused a silent failure once
  on this project — see `INSTALL.md`)
- **Periodically** (e.g. monthly) as a spot-check on an ongoing study

None of this requires lab-grade reference equipment — every test uses either
a well-established physiological signal or a simple physical measurement
(tape measure, goniometer).

Record every run in the [Results Log](#results-log) at the bottom.

---

## EEG (Unicorn Hybrid Black)

### Test E1 — Signal correctness (eyes-closed alpha test)

The definitive test that the full chain — electrode contact → byte decode →
band-power math — is working. **This has not yet been run and recorded for
this project; it's the most important outstanding test.**

**Steps:**
1. Fit the headset properly: gel or water on all 8 electrodes, REF/GND clips
   behind the ears with good skin contact.
2. Start a session with EEG enabled. Participant seated, relaxed, **eyes
   open**, for 15 seconds.
3. Instruct: **close eyes for 10 seconds**, then reopen.
4. Watch the alpha band (8–12 Hz) on the posterior/occipital channels.

**Pass:** alpha power visibly rises within ~1–2 s of eyes closing, and drops
again on reopening. This is the "Berger effect" — present in essentially
everyone with intact vision — so if it doesn't appear, don't assume the
subject is unusual; assume the pipeline or the fit is wrong.

**Fail:** no change, or channels are railed/flat throughout (check Test E3
first — it should have already caught bad contact before you got this far).

### Test E2 — Absolute scale calibration

Confirms the µV scale constant is numerically correct, not just directionally
correct. (`UnicornEegConnector.EegScaleUv` is override-able via PlayerPrefs
`EegScaleUv` specifically so this can be corrected without a rebuild.)

**Steps:**
1. Record the **same signal simultaneously** in this app and in the vendor's
   own **Unicorn Recorder** software (same headset, same session).
2. Compare the alpha peak-to-peak amplitude between the two recordings.
3. Compute the ratio; if it's not ~1.0, update the `EegScaleUv` override by
   that ratio.

**Pass:** after applying the correction, repeated alpha p2p amplitude in
this app matches Unicorn Recorder within a small tolerance (agree on one
before running this the first time, e.g. ±10%).

### Test E3 — Pre-session sanity (run every session, not just during validation)

Already automated — the app's pre-flight gate checks this before Begin is
enabled. Included here so the pass/fail thresholds are documented in one
place:

| Check | Threshold |
|---|---|
| Channel considered railed (open/disconnected electrode) | above 5000 µV |
| Channel considered flat (dead) | below 0.5 µV |
| Minimum clean channels to pass | 6 of 8 |

**Known gap:** this check only runs live, before recording. The saved
`eeg.csv` does not currently store a per-sample quality flag, so auditing a
*past* session for railing/flatness means opening the CSV and reading the
raw trace by eye.

---

## ZED 2i (motion capture)

### Test Z1 — Known-distance accuracy

**Steps:**
1. Place two markers a **precisely measured distance apart** (e.g. exactly
   1.000 m with a tape measure), both inside the camera's field of view, at
   a distance from the camera representative of real sessions (~2–4 m).
2. Record a short clip; read the tracked distance between the corresponding n
   joints/points.
3. Compare against Stereolabs' published depth-accuracy specification for
   the ZED 2i at that range (check their current documentation — don't
   assume a number here, as it varies with distance and firmware).

**Pass:** tracked distance is within the vendor's stated tolerance for that
range.

### Test Z2 — Joint angle accuracy (goniometer)

The test that matters clinically, since the app reports joint *angles*
(`Skeleton3D.activeAngle`), not raw positions.

**Steps:**
1. Have the participant/tester hold a joint at a known angle, measured with
   a physical goniometer (e.g. knee at 90°).
2. Read the app's live angle display for the same joint at the same moment.
3. Repeat for 2–3 different angles across the joint's range.

**Pass:** app-reported angle matches the goniometer within **±5°** — a
commonly used tolerance in clinical goniometry inter-rater reliability
literature; confirm this is tight enough for your study design before
relying on it.

### Test Z3 — Repeatability / jitter

**Steps:**
1. Hold a completely still pose for 10 seconds.
2. Watch a tracked joint's position (or the live angle readout) for
   frame-to-frame wobble.

**Pass:** minimal visible jitter. There's no numeric threshold computed by
the app for this today — it's a by-eye check. (A jittery-but-centered signal
still corrupts downstream ROM/smoothness analysis even if the average is
correct.)

### Test Z4 — Pre-session sanity (run every session)

Already automated:

| Check | Threshold |
|---|---|
| Minimum joints tracked to pass | 8 |

**Known gap:** the SDK reports a 0–1 confidence value per joint, and the app
already reads it live, but it is **not written into the saved
`zed_skeleton.json`** — so, same as EEG, a past session's tracking quality
can't currently be audited automatically after the fact.

---

## Known limitation (both sensors)

Tests E3/Z4 only run against the **live** stream, before recording starts.
Once a session is saved, there is currently no automated way to check
whether tracking/signal quality held up *during* the recording — only the
live pre-flight gate and these manual tests exist. A post-hoc data-quality
report (per-session % of frames with full tracking, EEG railed/flat
channel-time, etc.) would close this gap; not built yet.

---

## Results Log

| Date | Sensor | Test | Result | Tester | Notes |
|---|---|---|---|---|---|
| | | | | | |
