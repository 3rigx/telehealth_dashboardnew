import 'dart:convert';
import 'dart:ui';
import 'pressure_config.dart';
import 'skeleton_3d.dart';

class SessionInfo {
  final String participantId;
  final int sessionNumber;
  final int trialNumber;
  final String condition;
  final int recordingSeconds;
  final bool isRecording;
  final bool isPaused;

  const SessionInfo({
    this.participantId = 'P001',
    this.sessionNumber = 1,
    this.trialNumber = 1,
    this.condition = 'Motor',
    this.recordingSeconds = 0,
    this.isRecording = false,
    this.isPaused = false,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> j) => SessionInfo(
    participantId: j['participantId'] ?? 'P001',
    sessionNumber: j['sessionNumber'] ?? 1,
    trialNumber: j['trialNumber'] ?? 1,
    condition: j['condition'] ?? 'Motor',
    recordingSeconds: j['recordingSeconds'] ?? 0,
    isRecording: j['isRecording'] ?? false,
    isPaused: j['isPaused'] ?? false,
  );
}

class JointAngleData {
  final String name;
  final double angle;
  final double deviation;
  final double? targetMin;
  final double? targetMax;
  final int repCount;
  final int targetReps;
  final double trackingConfidence;
  final double trunkLean;

  const JointAngleData({
    required this.name,
    required this.angle,
    required this.deviation,
    this.targetMin,
    this.targetMax,
    this.repCount = 0,
    this.targetReps = 10,
    this.trackingConfidence = 1.0,
    this.trunkLean = 0.0,
  });

  factory JointAngleData.fromJson(Map<String, dynamic> j) => JointAngleData(
    name: j['name'] ?? '',
    angle: (j['angle'] ?? 0.0).toDouble(),
    deviation: (j['deviation'] ?? 0.0).toDouble(),
    targetMin: j['targetMin']?.toDouble(),
    targetMax: j['targetMax']?.toDouble(),
    repCount: j['repCount'] ?? 0,
    targetReps: j['targetReps'] ?? 10,
    trackingConfidence: (j['trackingConfidence'] ?? 1.0).toDouble(),
    trunkLean: (j['trunkLean'] ?? 0.0).toDouble(),
  );

  bool get inTarget => targetMin != null && targetMax != null &&
      angle >= targetMin! && angle <= targetMax!;
}

/// The four physical FSR pads the insole measures, each normalised 0..1.
/// Canonical pad names (medial / lateral — never midInner/midOuter), mirroring
/// Unity's [FSRState] fields Toe, Middle_Inner (medial), Middle_Outer (lateral),
/// Heel and the Arduino pin order A0..A3.
class FootZones {
  final double toe;
  final double medial;
  final double lateral;
  final double heel;

  const FootZones({
    this.toe = 0,
    this.medial = 0,
    this.lateral = 0,
    this.heel = 0,
  });

  double get sum => toe + medial + lateral + heel;
  double get forefoot => (toe + medial + lateral) / 3;

  /// Center of pressure within the foot, in normalised foot coordinates
  /// (x: 0 = medial … 1 = lateral, y: 0 = toe … 1 = heel). Returns the
  /// geometric centre when there is no load.
  Offset get cop {
    final total = sum;
    if (total <= 0) return const Offset(0.5, 0.5);
    // Approx zone centres (x medial→lateral, y toe→heel) for a generic insole.
    const pToe = Offset(0.50, 0.12);
    const pMedial = Offset(0.32, 0.48);
    const pLateral = Offset(0.68, 0.48);
    const pHeel = Offset(0.50, 0.86);
    final x = (pToe.dx * toe + pMedial.dx * medial + pLateral.dx * lateral + pHeel.dx * heel) / total;
    final y = (pToe.dy * toe + pMedial.dy * medial + pLateral.dy * lateral + pHeel.dy * heel) / total;
    return Offset(x, y);
  }

  factory FootZones.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const FootZones();
    return FootZones(
      toe:     (j['toe']     ?? 0.0).toDouble(),
      // Accept the legacy midInner/midOuter keys so an older recording/stream
      // still parses, but the canonical keys are medial/lateral.
      medial:  (j['medial']  ?? j['midInner'] ?? 0.0).toDouble(),
      lateral: (j['lateral'] ?? j['midOuter'] ?? 0.0).toDouble(),
      heel:    (j['heel']    ?? 0.0).toDouble(),
    );
  }
}

/// Live plantar-pressure state for the single insole (study default). [foot] is
/// the side the insole is on. The legacy two-insole broadcast is still parsed
/// (the configured study foot is shown) so the dashboard keeps working if the
/// capture engine is reverted to the two-insole rig.
class PlantarData {
  final String foot;             // "left" | "right"
  final FootZones zones;
  final double totalLoad;        // % of full-scale
  final double heelLoad;
  final double forefootLoad;
  final double stability;        // mediolateral COP SD (computed from history)
  final bool baselineUnderLoad;  // the unloaded baseline was captured with a pad loaded

  const PlantarData({
    this.foot = PressureConfig.foot,
    this.zones = const FootZones(),
    this.totalLoad = 0,
    this.heelLoad = 0,
    this.forefootLoad = 0,
    this.stability = 0,
    this.baselineUnderLoad = false,
  });

  bool get isLeft => PressureConfig.isLeft(foot);

  factory PlantarData.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] ?? 0.0).toDouble();

    // Single-insole shape (study default): {foot, insoleCount, zones:{...}, ...}.
    if (j['zones'] != null) {
      return PlantarData(
        foot: (j['foot'] ?? PressureConfig.foot).toString(),
        zones: FootZones.fromJson(j['zones'] as Map<String, dynamic>?),
        totalLoad: d('totalLoad'),
        heelLoad: d('heelLoad'),
        forefootLoad: d('forefootLoad'),
        stability: d('stability'),
        baselineUnderLoad: j['baselineUnderLoad'] == true,
      );
    }

    // Legacy two-insole broadcast: {left, right, asymmetry, ...}. Show the
    // configured study foot so the panel stays populated.
    final legacy = PressureConfig.isLeft(null) ? j['left'] : j['right'];
    return PlantarData(
      foot: PressureConfig.foot,
      zones: FootZones.fromJson(legacy as Map<String, dynamic>?),
      totalLoad: d('totalLoad'),
      heelLoad: d('heelLoad'),
      forefootLoad: d('forefootLoad'),
      stability: d('stability'),
    );
  }

  static PlantarData get demo => const PlantarData(
    foot: PressureConfig.foot,
    zones: FootZones(toe: 0.60, medial: 0.45, lateral: 0.30, heel: 0.85),
    totalLoad: 55.0, heelLoad: 85.0, forefootLoad: 45.0, stability: 0.64,
  );
}

class SensorStatus {
  final bool camera;
  final bool pressureInsole;   // FSR port is open (connected)
  final bool pressureStreaming; // FSR pad data is actually arriving
  final bool eeg;

  const SensorStatus({
    this.camera = false,
    this.pressureInsole = false,
    this.pressureStreaming = false,
    this.eeg = false,
  });

  factory SensorStatus.fromJson(Map<String, dynamic> j) => SensorStatus(
    camera:           j['camera']           ?? false,
    pressureInsole:   j['pressureInsole']   ?? false,
    pressureStreaming:j['pressureStreaming']?? false,
    eeg:              j['eeg']              ?? false,
  );
}

/// Live EEG metrics from the Unicorn (mean band power µV², per-channel RMS µV,
/// and signal-quality flags). Null when no EEG is streaming.
class EegData {
  final double theta;
  final double alpha;
  final double beta;
  final String quality;   // Good | Fair | Poor
  final String artifact;  // Low | High
  final List<double> channels; // per-channel RMS µV (length 8 when present)

  const EegData({
    this.theta = 0,
    this.alpha = 0,
    this.beta = 0,
    this.quality = '—',
    this.artifact = '—',
    this.channels = const [],
  });

  factory EegData.fromJson(Map<String, dynamic> j) => EegData(
    theta: (j['theta'] ?? 0).toDouble(),
    alpha: (j['alpha'] ?? 0).toDouble(),
    beta:  (j['beta']  ?? 0).toDouble(),
    quality:  j['quality']  ?? '—',
    artifact: j['artifact'] ?? '—',
    channels: List<double>.from(
        (j['channels'] ?? const []).map((e) => (e as num).toDouble())),
  );
}

class TelerehabState {
  final SessionInfo session;
  final List<JointAngleData> jointAngles;
  final PlantarData plantar;
  final SensorStatus sensors;
  final List<double> pressureHistory; // rolling buffer of total load
  final Skeleton3D? skeleton;         // 3D joint coords from the ZED, if present
  final EegData? eeg;                 // live EEG metrics, if streaming

  const TelerehabState({
    required this.session,
    required this.jointAngles,
    required this.plantar,
    required this.sensors,
    this.pressureHistory = const [],
    this.skeleton,
    this.eeg,
  });

  factory TelerehabState.fromJson(Map<String, dynamic> j) => TelerehabState(
    session:     SessionInfo.fromJson(j['session']  ?? {}),
    jointAngles: ((j['jointAngles'] ?? []) as List)
        .map((e) => JointAngleData.fromJson(e)).toList(),
    plantar:     PlantarData.fromJson(j['plantar']  ?? {}),
    sensors:     SensorStatus.fromJson(j['sensors'] ?? {}),
    pressureHistory: List<double>.from(
        (j['pressureHistory'] ?? []).map((e) => e.toDouble())),
    skeleton:    j['skeleton'] != null
        ? Skeleton3D.fromJson(j['skeleton'] as Map<String, dynamic>)
        : null,
    eeg:         j['eeg'] != null
        ? EegData.fromJson(j['eeg'] as Map<String, dynamic>)
        : null,
  );

  static TelerehabState get demo => TelerehabState(
    session: const SessionInfo(
      participantId: 'P012', sessionNumber: 3, trialNumber: 6,
      condition: 'Motor + Cognitive', recordingSeconds: 462, isRecording: true,
    ),
    jointAngles: [
      const JointAngleData(name: 'Knee Angle', angle: 52, deviation: 12,
          targetMin: 40, targetMax: 60, repCount: 6, targetReps: 10,
          trackingConfidence: 1.0, trunkLean: 4.0),
      const JointAngleData(name: 'Hip Angle', angle: 88, deviation: 8,
          targetMin: 80, targetMax: 100),
    ],
    plantar: PlantarData.demo,
    sensors: const SensorStatus(camera: true, pressureInsole: true, eeg: true),
    pressureHistory: [50,55,60,65,72,78,74,70,68,72,75,72],
    skeleton: Skeleton3D.seatedDemo(kneeAngleDeg: 52),
    eeg: const EegData(
      theta: 6.2, alpha: 9.8, beta: 4.4, quality: 'Good', artifact: 'Low',
      channels: [22, 18, 15, 19, 20, 24, 23, 14],
    ),
  );
}

class UnityCommand {
  final String action;
  final Map<String, dynamic> params;

  const UnityCommand(this.action, [this.params = const {}]);

  String toJson() => jsonEncode({'type': 'command', 'action': action, ...params});
}
