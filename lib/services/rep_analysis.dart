import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../models/session_models.dart' show jointAngleDeg, skeletonFromUnityJson;
import '../models/skeleton_3d.dart';
import 'session_repository.dart' show cumulativeTimeline;

/// Hysteresis rep counter on the knee **flexion** angle (0° = fully extended,
/// ~90° = flexed/hanging). One rep = extend below [extendThresh] then flex back
/// above [flexThresh]. This is the single source of truth for rep counting —
/// both the live run ([ProtocolRunner.feedSensor]) and the post-hoc recompute
/// over the recorded file use it, so the live display and the canonical value
/// can never drift apart in logic.
class KneeRepCounter {
  static const double extendThresh = 30;
  static const double flexThresh = 60;

  bool _extended = false;
  int count = 0;

  void feed(double flexionDeg) {
    if (!_extended && flexionDeg < extendThresh) {
      _extended = true;
    } else if (_extended && flexionDeg > flexThresh) {
      _extended = false;
      count++;
    }
  }

  void reset() {
    _extended = false;
  }
}

/// Right-knee flexion in degrees (0 = extended, ~90 = flexed) from a skeleton,
/// computed from the hip→knee→ankle interior angle. Falls back to the left leg
/// if the right joints are missing, or null if neither leg is tracked.
double? kneeFlexionDeg(Skeleton3D s) {
  Vec3? h = s['hipR'], k = s['kneeR'], a = s['ankleR'];
  if (h == null || k == null || a == null) {
    h = s['hipL'];
    k = s['kneeL'];
    a = s['ankleL'];
  }
  if (h == null || k == null || a == null) return null;
  // jointAngleDeg returns the interior angle (180° = straight leg); flexion is
  // the complement so it matches the live "flexion from horizontal" convention.
  return 180.0 - jointAngleDeg(h, k, a);
}

/// Result of recomputing reps from the authoritative recorded skeleton.
class RepAnalysis {
  final int totalReps;
  final Map<int, int> repsByBlock; // block number → reps
  const RepAnalysis(this.totalReps, this.repsByBlock);
}

/// Recompute reps from the recorded `zed_skeleton.json`, scoped to each
/// active-phase window (derived from the run markers). This is the canonical
/// count for analysis: it runs over the same data that was saved to disk, not
/// the lossy (and possibly mocked) live display stream.
///
/// Returns null when there is no skeleton file to analyse (the caller then
/// falls back to the live count). Returns a zero analysis when the file exists
/// but yields no usable frames/windows.
Future<RepAnalysis?> recomputeRepsFromRecording(
  String folderPath,
  List<({int startMs, int endMs, int block})> activeWindows,
) async {
  final sep = Platform.pathSeparator;
  final f = File('$folderPath${sep}zed_skeleton.json');
  if (!await f.exists()) return null;

  final samples = <({int tMs, double flexion})>[];
  try {
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final bodyFormat = j['bodyFormat'] ?? 1;
    final raw = <(int, Skeleton3D)>[];
    for (final fr in (j['frames'] as List? ?? const [])) {
      if (fr is! Map<String, dynamic>) continue;
      final sk = fr['skeleton'];
      if (sk is! Map<String, dynamic>) continue;
      final skeleton = skeletonFromUnityJson(sk, bodyFormat);
      if (skeleton != null) raw.add((fr['tMs'] ?? 0, skeleton));
    }
    // Unity writes t_ms as a per-frame delta; rebuild the real timeline exactly
    // as the replay loader does, so windows and samples share one clock.
    final times = cumulativeTimeline([for (final r in raw) r.$1]);
    for (var i = 0; i < raw.length; i++) {
      final flex = kneeFlexionDeg(raw[i].$2);
      if (flex != null) samples.add((tMs: times[i], flexion: flex));
    }
  } catch (e) {
    debugPrint('recomputeRepsFromRecording: failed to parse skeleton: $e');
    return null;
  }

  if (samples.isEmpty || activeWindows.isEmpty) return const RepAnalysis(0, {});

  final byBlock = <int, int>{};
  var total = 0;
  for (final w in activeWindows) {
    final counter = KneeRepCounter();
    for (final s in samples) {
      if (s.tMs >= w.startMs && s.tMs < w.endMs) counter.feed(s.flexion);
    }
    byBlock[w.block] = counter.count;
    total += counter.count;
  }
  return RepAnalysis(total, byBlock);
}
