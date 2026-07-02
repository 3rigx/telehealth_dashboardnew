import '../models/telerehab_state.dart';

/// Traffic-light status for one sensor in the pre-flight gate.
enum SignalLevel { ok, warn, bad }

/// Assessment of one enabled sensor just before a run begins.
class SensorSignal {
  final String label; // e.g. "Camera (ZED)"
  final SignalLevel level;
  final String detail; // e.g. "18 joints tracked" / "3 channels railed"
  const SensorSignal(this.label, this.level, this.detail);
}

/// Pre-flight signal-quality report over the sensors a protocol actually uses.
class SignalReport {
  final List<SensorSignal> sensors;
  const SignalReport(this.sensors);

  bool get hasChecks => sensors.isNotEmpty;
  bool get allOk => sensors.every((s) => s.level == SignalLevel.ok);
  int get problems => sensors.where((s) => s.level != SignalLevel.ok).length;
}

/// Thresholds for the gate. Kept together and named so they're easy to tune and
/// unit-test. EEG values are per-channel RMS in µV (as broadcast by Unity).
class SignalThresholds {
  /// Above this a channel is almost certainly a floating/open electrode (the
  /// unworn Unicorn rails to ~1.49M µV p2p); well above any physiological EEG.
  static const double eegRailUv = 5000;

  /// Below this a channel is effectively dead (flat line).
  static const double eegFlatUv = 0.5;

  /// How many of the (up to 8) EEG channels must be clean to pass.
  static const int eegMinGood = 6;

  /// A tracked ZED body should expose at least this many named joints.
  static const int zedMinJoints = 8;
}

/// Assess whether the live stream is good enough to start recording. Only the
/// sensors the protocol enables are checked. This catches the failure modes we
/// already hit in the field — FSR pointed at the wrong COM port (all zeros),
/// the EEG worn poorly / not at all (railed channels), and no body in frame —
/// *before* a session is wasted recording them.
SignalReport assessSignalQuality(
  TelerehabState s, {
  required bool zed,
  required bool fsr,
  required bool eeg,
}) {
  final out = <SensorSignal>[];

  if (zed) {
    final sk = s.skeleton;
    final n = sk?.joints.length ?? 0;
    if (sk == null || n == 0) {
      out.add(const SensorSignal('Camera (ZED)', SignalLevel.bad, 'No body tracked'));
    } else if (n < SignalThresholds.zedMinJoints) {
      out.add(SensorSignal('Camera (ZED)', SignalLevel.warn, 'Only $n joints tracked'));
    } else {
      out.add(SensorSignal('Camera (ZED)', SignalLevel.ok, '$n joints tracked'));
    }
  }

  if (fsr) {
    final load = s.plantar.left.sum + s.plantar.right.sum;
    if (load <= 0) {
      out.add(const SensorSignal('Pressure insoles', SignalLevel.warn,
          'Reading zero — check the insole COM port / contact'));
    } else {
      out.add(SensorSignal('Pressure insoles', SignalLevel.ok,
          'Load ${s.plantar.totalLoad.toStringAsFixed(0)}%'));
    }
  }

  if (eeg) {
    final ch = s.eeg?.channels ?? const <double>[];
    if (ch.isEmpty) {
      out.add(const SensorSignal('EEG (Unicorn)', SignalLevel.bad, 'No EEG streaming'));
    } else {
      var good = 0, railed = 0, flat = 0;
      for (final v in ch) {
        final a = v.abs();
        if (a > SignalThresholds.eegRailUv) {
          railed++;
        } else if (a < SignalThresholds.eegFlatUv) {
          flat++;
        } else {
          good++;
        }
      }
      final level = good >= SignalThresholds.eegMinGood
          ? SignalLevel.ok
          : good == 0
              ? SignalLevel.bad
              : SignalLevel.warn;
      final bits = <String>['$good/${ch.length} clean'];
      if (railed > 0) bits.add('$railed railed');
      if (flat > 0) bits.add('$flat flat');
      out.add(SensorSignal('EEG (Unicorn)', level, bits.join(' · ')));
    }
  }

  return SignalReport(out);
}
