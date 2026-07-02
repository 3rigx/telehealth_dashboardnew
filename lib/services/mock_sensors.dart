import 'dart:math';
import '../models/session_models.dart';
import '../models/skeleton_3d.dart';
import '../models/telerehab_state.dart';

/// Deterministic per-sensor mock signal generators. Used two ways:
///  - live overlay: any sensor marked "mock" in Settings animates from these
///    while non-mocked sensors keep showing real Unity data;
///  - mock replay: [buildMockSession] synthesises a full recorded session so
///    the replay screen can be exercised without files on disk.
class MockSensors {
  /// Knee angle in the seated-demo convention (0° = extended, 90° = hanging),
  /// as a repeating rep cycle: 2 s extend, 1 s hold, 2 s flex, 3 s rest.
  static double kneeAngleAt(double tSec) {
    const rest = 80.0, extended = 15.0, cycle = 8.0;
    final t = tSec % cycle;
    double k; // 0 = rest .. 1 = fully extended
    if (t < 2) {
      k = _ease(t / 2);
    } else if (t < 3) {
      k = 1;
    } else if (t < 5) {
      k = 1 - _ease((t - 3) / 2);
    } else {
      k = 0;
    }
    // small tremor so charts look organic
    final tremor = 1.5 * sin(tSec * 9) * k;
    return rest - (rest - extended) * k + tremor;
  }

  static double _ease(double x) => x * x * (3 - 2 * x);

  static Skeleton3D skeletonAt(double tSec) =>
      Skeleton3D.seatedDemo(kneeAngleDeg: kneeAngleAt(tSec));

  /// Plantar pressure for both feet, normalised 0..1. During extension the
  /// active (right) heel unloads and the left side takes more weight.
  static (FootZones left, FootZones right) fsrAt(double tSec) {
    final angle = kneeAngleAt(tSec);
    final k = (80 - angle) / 65; // 0 rest .. 1 extended
    final sway = 0.04 * sin(tSec * 1.7);

    final left = FootZones(
      toe: (0.35 + 0.25 * k + sway).clamp(0.0, 1.0),
      midInner: (0.30 + 0.15 * k).clamp(0.0, 1.0),
      midOuter: (0.28 + 0.12 * k - sway).clamp(0.0, 1.0),
      heel: (0.65 + 0.20 * k).clamp(0.0, 1.0),
    );
    final right = FootZones(
      toe: (0.40 - 0.25 * k - sway).clamp(0.0, 1.0),
      midInner: (0.32 - 0.18 * k).clamp(0.0, 1.0),
      midOuter: (0.30 - 0.15 * k + sway).clamp(0.0, 1.0),
      heel: (0.70 - 0.45 * k).clamp(0.0, 1.0),
    );
    return (left, right);
  }

  static PlantarData plantarAt(double tSec, {List<double>? history}) {
    final (left, right) = fsrAt(tSec);
    final total = (left.sum + right.sum) / 8 * 100;
    final asym = ((left.sum - right.sum) / max(0.001, left.sum + right.sum)).abs() * 100;
    return PlantarData(
      left: left,
      right: right,
      totalLoad: total,
      heelLoad: (left.heel + right.heel) / 2 * 100,
      forefootLoad: (left.forefoot + right.forefoot) / 2 * 100,
      asymmetry: asym,
      stability: 0.4 + 0.3 * sin(tSec * 0.6).abs(),
    );
  }

  static JointAngleData kneeJointAt(double tSec) {
    final angle = kneeAngleAt(tSec);
    return JointAngleData(
      name: 'Knee Angle',
      angle: angle,
      deviation: angle - 50,
      targetMin: 40,
      targetMax: 60,
      repCount: (tSec ~/ 8),
      targetReps: 10,
      trackingConfidence: 1.0,
      trunkLean: 2 + 4 * ((80 - angle) / 65),
    );
  }

  /// Plausible resting-EEG metrics with slow drift, plus 8 per-channel RMS values.
  static EegData eegAt(double tSec) {
    final alpha = 9.0 + 2.0 * sin(tSec * 0.30);
    final theta = 6.0 + 1.5 * sin(tSec * 0.21 + 1);
    final beta  = 4.0 + 1.2 * sin(tSec * 0.50 + 2);
    final channels = List<double>.generate(
        8, (i) => 16 + 9 * (0.5 + 0.5 * sin(tSec * 0.7 + i * 0.8)));
    return EegData(
      theta: theta, alpha: alpha, beta: beta,
      quality: 'Good', artifact: 'Low',
      channels: channels,
    );
  }

  /// A full synthetic 90 s session at 30 Hz, in the exact shape a real one has
  /// after loading from disk.
  static RecordedSession buildMockSession({int seconds = 90, double hz = 30}) {
    final frames = <SkeletonFrame>[];
    final fsr = <FsrSample>[];
    final n = (seconds * hz).round();
    for (var i = 0; i < n; i++) {
      final tSec = i / hz;
      final tMs = (tSec * 1000).round();
      frames.add(SkeletonFrame(tMs: tMs, skeleton: skeletonAt(tSec)));
      final (left, right) = fsrAt(tSec);
      fsr.add(FsrSample(tMs: tMs, left: left, right: right));
    }
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final sessionId =
        '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}-${two(now.minute)}-${two(now.second)}_Motion';
    return RecordedSession(
      isMock: true,
      summary: SessionSummary(
        patientId: 'MOCK',
        sessionId: sessionId,
        folderPath: '',
        manifest: RecordedManifest(
          patientId: 'MOCK',
          sessionId: sessionId,
          exerciseClass: 'Motion',
          trialNumber: 1,
          startUtc: now.toUtc().toIso8601String(),
          endUtc: now.toUtc().add(Duration(seconds: seconds)).toIso8601String(),
          zed: SensorEntry(
              enabled: true, source: 'mock', file: '', sampleRateHz: hz, sampleCount: n),
          fsr: SensorEntry(
              enabled: true, source: 'mock', file: '', sampleRateHz: hz, sampleCount: n),
        ),
      ),
      frames: frames,
      fsr: fsr,
    );
  }
}
