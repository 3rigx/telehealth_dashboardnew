import 'dart:math';
import 'skeleton_3d.dart';
import 'telerehab_state.dart';

/// Dart mirror of Unity's SessionManifest (session.json).
class RecordedManifest {
  final int schemaVersion;
  final String patientId;
  final String sessionId;
  final String mode; // Exercise | Prediction
  final String exerciseClass; // Idle | Motion | MotionCognitive
  final int trialNumber;
  final String startUtc;
  final String endUtc;
  final int bodyFormat;
  final SensorEntry zed;
  final SensorEntry fsr;
  final SensorEntry eeg;

  const RecordedManifest({
    this.schemaVersion = 1,
    this.patientId = '',
    this.sessionId = '',
    this.mode = 'Exercise',
    this.exerciseClass = 'Motion',
    this.trialNumber = 0,
    this.startUtc = '',
    this.endUtc = '',
    this.bodyFormat = 1,
    this.zed = const SensorEntry(),
    this.fsr = const SensorEntry(),
    this.eeg = const SensorEntry(),
  });

  factory RecordedManifest.fromJson(Map<String, dynamic> j) => RecordedManifest(
        schemaVersion: j['schemaVersion'] ?? 1,
        patientId: j['patientId'] ?? '',
        sessionId: j['sessionId'] ?? '',
        mode: j['mode'] ?? 'Exercise',
        exerciseClass: j['exerciseClass'] ?? 'Motion',
        trialNumber: j['trialNumber'] ?? 0,
        startUtc: j['startUtc'] ?? '',
        endUtc: j['endUtc'] ?? '',
        bodyFormat: j['bodyFormat'] ?? 1,
        zed: SensorEntry.fromJson(j['zed']),
        fsr: SensorEntry.fromJson(j['fsr']),
        eeg: SensorEntry.fromJson(j['eeg']),
      );

  DateTime? get start => DateTime.tryParse(startUtc);
  DateTime? get end => DateTime.tryParse(endUtc);
  Duration? get duration {
    final s = start, e = end;
    if (s == null || e == null) return null;
    return e.difference(s);
  }
}

class SensorEntry {
  final bool enabled;
  final String source;
  final String file;
  final double sampleRateHz;
  final int sampleCount;
  final int channels;

  const SensorEntry({
    this.enabled = false,
    this.source = '',
    this.file = '',
    this.sampleRateHz = 0,
    this.sampleCount = 0,
    this.channels = 0,
  });

  factory SensorEntry.fromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return const SensorEntry();
    return SensorEntry(
      enabled: j['enabled'] ?? false,
      source: j['source'] ?? '',
      file: j['file'] ?? '',
      sampleRateHz: (j['sampleRateHz'] ?? 0).toDouble(),
      sampleCount: j['sampleCount'] ?? 0,
      channels: j['channels'] ?? 0,
    );
  }
}

/// One row of fsr.csv. Raw values are the sensor's integer ADC readings.
class FsrSample {
  final int tMs;
  final FootZones left;
  final FootZones right;
  const FsrSample({required this.tMs, required this.left, required this.right});
}

/// One frame of zed_skeleton.json mapped into the named-joint skeleton the
/// renderer understands.
class SkeletonFrame {
  final int tMs;
  final Skeleton3D skeleton;
  const SkeletonFrame({required this.tMs, required this.skeleton});
}

/// One row of eeg.csv — 8 channels (µV) at a cumulative timestamp.
class EegFrame {
  final int tMs;
  final List<double> channels; // length 8
  const EegFrame({required this.tMs, required this.channels});
}

/// One row of markers.csv — a protocol block/phase event, timestamped in ms
/// since recording start. Written by the dashboard during a live protocol run.
class SessionMarker {
  final int tMs;
  final String event; // instruction | active | reset | pause | resume | end
  final int block;
  final String classId;
  final String className;
  final String baseToken;

  const SessionMarker({
    required this.tMs,
    required this.event,
    required this.block,
    required this.classId,
    required this.className,
    required this.baseToken,
  });

  static SessionMarker? tryParseCsv(String line) {
    final c = _splitCsv(line);
    if (c.length < 6) return null;
    final t = int.tryParse(c[0].trim());
    if (t == null) return null;
    return SessionMarker(
      tMs: t,
      event: c[1].trim(),
      block: int.tryParse(c[2].trim()) ?? 0,
      classId: c[3],
      className: c[4],
      baseToken: c[5],
    );
  }
}

/// A contiguous block span on the replay timeline, coloured by its class.
class BlockSegment {
  final int blockNumber;
  final int startMs;
  final int endMs;
  final String classId;
  final String className;
  final int colorValue;
  const BlockSegment({
    required this.blockNumber,
    required this.startMs,
    required this.endMs,
    required this.classId,
    required this.className,
    required this.colorValue,
  });
}

/// Minimal RFC-4180-ish CSV line splitter (handles quoted fields + "" escapes).
List<String> _splitCsv(String line) {
  final out = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        sb.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      out.add(sb.toString());
      sb.clear();
    } else {
      sb.write(ch);
    }
  }
  out.add(sb.toString());
  return out;
}

/// Fallback segment colours used when no protocol.json snapshot is present.
const _segPalette = <int>[
  0xFF1A6EFA, 0xFF00C896, 0xFFFF8C00, 0xFFBB86FC, 0xFF00D4FF, 0xFFFF3B55,
];

/// Lightweight entry for the session browser — built from folder names and
/// the manifest, without loading sensor data.
class SessionSummary {
  final String patientId;
  final String sessionId; // folder name, e.g. 2026-06-11_14-03-22_Motion
  final String folderPath;
  final RecordedManifest manifest;

  const SessionSummary({
    required this.patientId,
    required this.sessionId,
    required this.folderPath,
    required this.manifest,
  });

  String get exerciseClass => manifest.exerciseClass;
  String get classDisplay => switch (manifest.exerciseClass) {
        'MotionCognitive' => 'Motion + Cognitive',
        _ => manifest.exerciseClass,
      };

  /// Local start time parsed from the folder name (yyyy-MM-dd_HH-mm-ss_Class).
  DateTime? get startedAt {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})')
        .firstMatch(sessionId);
    if (m == null) return manifest.start?.toLocal();
    return DateTime(
      int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!),
      int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!),
    );
  }
}

/// A fully loaded session ready for replay.
class RecordedSession {
  final SessionSummary summary;
  final List<SkeletonFrame> frames;
  final List<FsrSample> fsr;
  final List<EegFrame> eeg;

  /// Protocol block/phase events (from markers.csv), and the class id→colour
  /// map (from the protocol.json snapshot). Empty for non-protocol sessions.
  final List<SessionMarker> markers;
  final Map<String, int> classColors;

  /// True when this session was synthesised in-app (mock replay data).
  final bool isMock;

  RecordedSession({
    required this.summary,
    required this.frames,
    required this.fsr,
    this.eeg = const [],
    this.markers = const [],
    this.classColors = const {},
    this.isMock = false,
  });

  bool get hasEeg => eeg.isNotEmpty;
  bool get hasProtocol => markers.isNotEmpty;

  int get durationMs {
    var d = 0;
    if (frames.isNotEmpty) d = max(d, frames.last.tMs);
    if (fsr.isNotEmpty) d = max(d, fsr.last.tMs);
    if (markers.isNotEmpty) d = max(d, markers.last.tMs);
    return d;
  }

  /// Contiguous, class-coloured block spans built from the markers — used to
  /// draw the replay block timeline. Each block runs from its `instruction`
  /// event to the next block's start (or the final `end` event).
  late final List<BlockSegment> blockSegments = _buildSegments();

  List<BlockSegment> _buildSegments() {
    if (markers.isEmpty) return const [];
    final starts = [for (final m in markers) if (m.event == 'instruction') m];
    if (starts.isEmpty) return const [];
    final lastMs = markers.last.tMs;

    final fallback = <String, int>{};
    var next = 0;
    int colorFor(String id) {
      final c = classColors[id];
      if (c != null) return c;
      return fallback.putIfAbsent(id, () {
        final col = _segPalette[next % _segPalette.length];
        next++;
        return col;
      });
    }

    final out = <BlockSegment>[];
    for (var i = 0; i < starts.length; i++) {
      final s = starts[i];
      final end = i + 1 < starts.length ? starts[i + 1].tMs : lastMs;
      out.add(BlockSegment(
        blockNumber: s.block,
        startMs: s.tMs,
        endMs: end,
        classId: s.classId,
        className: s.className,
        colorValue: colorFor(s.classId),
      ));
    }
    return out;
  }

  /// The block segment containing [tMs], or null if none.
  BlockSegment? segmentAt(int tMs) {
    for (final b in blockSegments) {
      if (tMs >= b.startMs && tMs < b.endMs) return b;
    }
    return blockSegments.isNotEmpty && tMs >= blockSegments.last.endMs
        ? blockSegments.last
        : null;
  }

  /// 95th-percentile of raw FSR readings, used to normalise the heatmap so
  /// both mock (0..1) and hardware (0..1023) scales display correctly.
  late final double fsrScale = _computeFsrScale();

  double _computeFsrScale() {
    final all = <double>[];
    for (final s in fsr) {
      all.addAll([
        s.left.toe, s.left.midInner, s.left.midOuter, s.left.heel,
        s.right.toe, s.right.midInner, s.right.midOuter, s.right.heel,
      ]);
    }
    final nonZero = all.where((v) => v > 0).toList()..sort();
    if (nonZero.isEmpty) return 1;
    return nonZero[(nonZero.length * 0.95).floor().clamp(0, nonZero.length - 1)];
  }
}

// ── ZED body-format joint maps ────────────────────────────────────────────────
// Maps the renderer's named joints to ZED joint indices.

const Map<String, int> _body34 = {
  'pelvis': 0, 'chest': 2, 'neck': 3, 'head': 26,
  'shoulderL': 5, 'elbowL': 6, 'wristL': 7,
  'shoulderR': 12, 'elbowR': 13, 'wristR': 14,
  'hipL': 18, 'kneeL': 19, 'ankleL': 20, 'toeL': 21,
  'hipR': 22, 'kneeR': 23, 'ankleR': 24, 'toeR': 25,
};

const Map<String, int> _body18 = {
  'head': 0, 'neck': 1,
  'shoulderR': 2, 'elbowR': 3, 'wristR': 4,
  'shoulderL': 5, 'elbowL': 6, 'wristL': 7,
  'hipR': 8, 'kneeR': 9, 'ankleR': 10,
  'hipL': 11, 'kneeL': 12, 'ankleL': 13,
};

const Map<String, int> _body38 = {
  'pelvis': 0, 'chest': 2, 'neck': 3, 'head': 5,
  'shoulderL': 12, 'elbowL': 14, 'wristL': 16,
  'shoulderR': 13, 'elbowR': 15, 'wristR': 17,
  'hipL': 18, 'kneeL': 20, 'ankleL': 22, 'toeL': 32,
  'hipR': 19, 'kneeR': 21, 'ankleR': 23, 'toeR': 33,
};

Map<String, int> jointMapForFormat(int bodyFormat) => switch (bodyFormat) {
      0 => _body18,
      2 => _body38,
      _ => _body34,
    };

/// Convert one Unity SkeletonState frame (JsonUtility shape) to a Skeleton3D.
/// `JointPos` is a list of {"x","y","z"} maps in metres.
Skeleton3D? skeletonFromUnityJson(Map<String, dynamic> sk, int bodyFormat) {
  final raw = sk['JointPos'];
  if (raw is! List || raw.isEmpty) return null;
  final map = jointMapForFormat(sk['m_Format'] is int ? sk['m_Format'] : bodyFormat);
  final joints = <String, Vec3>{};
  map.forEach((name, idx) {
    if (idx < raw.length) {
      final p = raw[idx];
      if (p is Map) {
        joints[name] = Vec3(
          (p['x'] ?? 0).toDouble(),
          (p['y'] ?? 0).toDouble(),
          (p['z'] ?? 0).toDouble(),
        );
      }
    }
  });
  if (joints.isEmpty) return null;

  // Pelvis fallback for formats without one (BODY_18): midpoint of the hips.
  if (!joints.containsKey('pelvis') &&
      joints.containsKey('hipL') && joints.containsKey('hipR')) {
    joints['pelvis'] = Vec3.lerp(joints['hipL']!, joints['hipR']!, 0.5);
  }
  if (!joints.containsKey('chest') &&
      joints.containsKey('neck') && joints.containsKey('pelvis')) {
    joints['chest'] = Vec3.lerp(joints['pelvis']!, joints['neck']!, 0.7);
  }
  return Skeleton3D(joints: joints);
}

/// Interior angle (degrees) at joint b formed by segments b→a and b→c.
/// 180° = fully extended/straight.
double jointAngleDeg(Vec3 a, Vec3 b, Vec3 c) {
  final v1 = a - b, v2 = c - b;
  final l1 = sqrt(v1.x * v1.x + v1.y * v1.y + v1.z * v1.z);
  final l2 = sqrt(v2.x * v2.x + v2.y * v2.y + v2.z * v2.z);
  if (l1 < 1e-6 || l2 < 1e-6) return 0;
  final d = (v1.x * v2.x + v1.y * v2.y + v1.z * v2.z) / (l1 * l2);
  return acos(d.clamp(-1.0, 1.0)) * 180 / pi;
}
