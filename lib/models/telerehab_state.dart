import 'dart:convert';

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

class PlantarData {
  final List<double> leftFoot;   // 16 sensor values 0..1
  final List<double> rightFoot;  // 16 sensor values 0..1
  final double totalLoad;        // %BW
  final double heelLoad;
  final double forefootLoad;
  final double asymmetry;        // %
  final double stability;        // COP SD cm

  const PlantarData({
    this.leftFoot = const [],
    this.rightFoot = const [],
    this.totalLoad = 0,
    this.heelLoad = 0,
    this.forefootLoad = 0,
    this.asymmetry = 0,
    this.stability = 0,
  });

  factory PlantarData.fromJson(Map<String, dynamic> j) => PlantarData(
    leftFoot:    List<double>.from((j['leftFoot']  ?? []).map((e) => e.toDouble())),
    rightFoot:   List<double>.from((j['rightFoot'] ?? []).map((e) => e.toDouble())),
    totalLoad:   (j['totalLoad']   ?? 0.0).toDouble(),
    heelLoad:    (j['heelLoad']    ?? 0.0).toDouble(),
    forefootLoad:(j['forefootLoad']?? 0.0).toDouble(),
    asymmetry:   (j['asymmetry']   ?? 0.0).toDouble(),
    stability:   (j['stability']   ?? 0.0).toDouble(),
  );

  static PlantarData get demo => PlantarData(
    leftFoot:  [0.2,0.3,0.4,0.3, 0.5,0.9,0.7,0.4, 0.3,0.5,0.4,0.2, 0.6,0.8,0.9,0.7],
    rightFoot: [0.2,0.4,0.3,0.2, 0.6,0.9,0.8,0.5, 0.3,0.5,0.4,0.2, 0.7,0.9,0.9,0.8],
    totalLoad: 72.4, heelLoad: 34.1, forefootLoad: 38.3, asymmetry: 8.7, stability: 0.64,
  );
}

class SensorStatus {
  final bool camera;
  final bool pressureInsole;
  final bool eeg;

  const SensorStatus({this.camera = false, this.pressureInsole = false, this.eeg = false});

  factory SensorStatus.fromJson(Map<String, dynamic> j) => SensorStatus(
    camera:         j['camera']         ?? false,
    pressureInsole: j['pressureInsole'] ?? false,
    eeg:            j['eeg']            ?? false,
  );
}

class TelerehabState {
  final SessionInfo session;
  final List<JointAngleData> jointAngles;
  final PlantarData plantar;
  final SensorStatus sensors;
  final List<double> pressureHistory; // rolling buffer of total load

  const TelerehabState({
    required this.session,
    required this.jointAngles,
    required this.plantar,
    required this.sensors,
    this.pressureHistory = const [],
  });

  factory TelerehabState.fromJson(Map<String, dynamic> j) => TelerehabState(
    session:     SessionInfo.fromJson(j['session']  ?? {}),
    jointAngles: ((j['jointAngles'] ?? []) as List)
        .map((e) => JointAngleData.fromJson(e)).toList(),
    plantar:     PlantarData.fromJson(j['plantar']  ?? {}),
    sensors:     SensorStatus.fromJson(j['sensors'] ?? {}),
    pressureHistory: List<double>.from(
        (j['pressureHistory'] ?? []).map((e) => e.toDouble())),
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
  );
}

class UnityCommand {
  final String action;
  final Map<String, dynamic> params;

  const UnityCommand(this.action, [this.params = const {}]);

  String toJson() => jsonEncode({'type': 'command', 'action': action, ...params});
}
