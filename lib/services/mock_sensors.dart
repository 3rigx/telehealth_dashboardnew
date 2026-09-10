import 'dart:math';
import '../models/pressure_config.dart';
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

  /// Single-insole plantar pressure, normalised 0..1: a heel→toe roll that
  /// shifts weight forward as the knee extends.
  static FootZones fsrAt(double tSec) {
    final angle = kneeAngleAt(tSec);
    final k = (80 - angle) / 65; // 0 rest .. 1 extended
    final sway = 0.04 * sin(tSec * 1.7);

    return FootZones(
      toe: (0.40 + 0.30 * k + sway).clamp(0.0, 1.0),
      medial: (0.32 + 0.16 * k).clamp(0.0, 1.0),
      lateral: (0.30 + 0.12 * k - sway).clamp(0.0, 1.0),
      heel: (0.70 - 0.30 * k).clamp(0.0, 1.0),
    );
  }

  static PlantarData plantarAt(double tSec, {List<double>? history}) {
    final z = fsrAt(tSec);
    return PlantarData(
      foot: PressureConfig.foot,
      zones: z,
      totalLoad: z.sum / 4 * 100,
      heelLoad: z.heel * 100,
      forefootLoad: z.forefoot * 100,
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
      final z = fsrAt(tSec);
      const empty = FootZones();
      fsr.add(FsrSample(
        tMs: tMs,
        left: PressureConfig.isLeft(PressureConfig.foot) ? z : empty,
        right: PressureConfig.isLeft(PressureConfig.foot) ? empty : z,
      ));
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
          schemaVersion: 2,
          patientId: 'MOCK',
          sessionId: sessionId,
          exerciseClass: 'Motion',
          trialNumber: 1,
          startUtc: now.toUtc().toIso8601String(),
          endUtc: now.toUtc().add(Duration(seconds: seconds)).toIso8601String(),
          zed: SensorEntry(
              enabled: true, source: 'mock', file: '', sampleRateHz: hz, sampleCount: n),
          fsr: SensorEntry(
              enabled: true, source: 'mock', file: '', sampleRateHz: hz, sampleCount: n,
              insoleCount: 1, foot: PressureConfig.foot, channelNames: PressureConfig.channelNames),
        ),
      ),
      frames: frames,
      fsr: fsr,
    );
  }
}
