import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/session_models.dart';
import '../models/skeleton_3d.dart';
import '../models/telerehab_state.dart';

/// One detected repetition in the knee-angle series.
class RepInfo {
  final int index; // 1-based
  final int startMs;
  final int endMs;
  final double peakAngle; // max extension (interior angle, deg)
  final double rom; // range of motion within the rep (deg)
  final double smoothness; // 0..1, higher = smoother (jerk-based)
  const RepInfo({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.peakAngle,
    required this.rom,
    required this.smoothness,
  });

  double get durationSec => (endMs - startMs) / 1000;
}

/// Whole-session metrics shown on the report card.
class SessionAnalytics {
  final String activeSide; // 'R' | 'L'
  final List<(int, double)> angleSeries; // (tMs, interior knee angle deg)
  final List<(int, double)> loadSeries; // (tMs, total load % of scale)
  final List<(int, double)> asymmetrySeries; // (tMs, signed L−R %)
  final List<RepInfo> reps;
  final double meanRom;
  final double bestRom;
  final double meanRepDuration;
  final double meanAsymmetry;
  final double meanSmoothness;

  const SessionAnalytics({
    required this.activeSide,
    required this.angleSeries,
    required this.loadSeries,
    required this.asymmetrySeries,
    required this.reps,
    required this.meanRom,
    required this.bestRom,
    required this.meanRepDuration,
    required this.meanAsymmetry,
    required this.meanSmoothness,
  });

  static const empty = SessionAnalytics(
    activeSide: 'R',
    angleSeries: [],
    loadSeries: [],
    asymmetrySeries: [],
    reps: [],
    meanRom: 0,
    bestRom: 0,
    meanRepDuration: 0,
    meanAsymmetry: 0,
    meanSmoothness: 0,
  );
}

/// Playback + analysis engine for one loaded [RecordedSession].
class ReplayEngine extends ChangeNotifier {
  RecordedSession? _session;
  SessionAnalytics _analytics = SessionAnalytics.empty;

  Timer? _ticker;
  int _playheadMs = 0;
  double _speed = 1.0;
  bool _playing = false;
  DateTime? _lastTick;

  RecordedSession? get session => _session;
  SessionAnalytics get analytics => _analytics;
  int get playheadMs => _playheadMs;
  int get durationMs => _session?.durationMs ?? 0;
  double get speed => _speed;
  bool get playing => _playing;

  void load(RecordedSession s) {
    stop();
    _session = s;
    _playheadMs = 0;
    _analytics = analyse(s);
    notifyListeners();
  }

  void unload() {
    stop();
    _session = null;
    _analytics = SessionAnalytics.empty;
    notifyListeners();
  }

  // ── transport ──────────────────────────────────────────────────────────────

  void play() {
    if (_session == null || _playing) return;
    if (_playheadMs >= durationMs) _playheadMs = 0;
    _playing = true;
    _lastTick = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final now = DateTime.now();
      final dt = now.difference(_lastTick!).inMicroseconds / 1000.0;
      _lastTick = now;
      _playheadMs += (dt * _speed).round();
      if (_playheadMs >= durationMs) {
        _playheadMs = durationMs;
        pause();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    _playing = false;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  void stop() {
    pause();
    _playheadMs = 0;
    notifyListeners();
  }

  void togglePlay() => _playing ? pause() : play();

  void seekMs(int ms) {
    _playheadMs = ms.clamp(0, durationMs);
    notifyListeners();
  }

  void setSpeed(double v) {
    _speed = v;
    notifyListeners();
  }

  void stepFrames(int delta) {
    final frames = _session?.frames;
    if (frames == null || frames.isEmpty) return;
    final i = (_indexAt(frames.map((f) => f.tMs).toList(), _playheadMs) + delta)
        .clamp(0, frames.length - 1);
    pause();
    seekMs(frames[i].tMs);
  }

  // ── frame lookup ───────────────────────────────────────────────────────────

  static int _indexAt(List<int> times, int tMs) {
    if (times.isEmpty) return 0;
    var lo = 0, hi = times.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (times[mid] <= tMs) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Skeleton at the playhead, annotated with the live joint angle so the
  /// renderer draws the angle arc.
  Skeleton3D? currentSkeleton() {
    final s = _session;
    if (s == null || s.frames.isEmpty) return null;
    final i = _indexAt(s.frames.map((f) => f.tMs).toList(), _playheadMs);
    final sk = s.frames[i].skeleton;
    final side = _analytics.activeSide;
    final hip = sk['hip$side'], knee = sk['knee$side'], ankle = sk['ankle$side'];
    if (hip != null && knee != null && ankle != null) {
      return Skeleton3D(
        joints: sk.joints,
        confidence: sk.confidence,
        activeJoint: 'knee$side',
        activeAngle: jointAngleDeg(hip, knee, ankle),
      );
    }
    return sk;
  }

  FsrSample? currentFsr() {
    final s = _session;
    if (s == null || s.fsr.isEmpty) return null;
    return s.fsr[_indexAt(s.fsr.map((f) => f.tMs).toList(), _playheadMs)];
  }

  /// Normalised (0..1) zones at the playhead for the heatmap.
  (FootZones, FootZones)? currentZonesNormalised() {
    final s = _session;
    final f = currentFsr();
    if (s == null || f == null) return null;
    final k = s.fsrScale <= 0 ? 1.0 : 1.0 / s.fsrScale;
    FootZones n(FootZones z) => FootZones(
          toe: (z.toe * k).clamp(0.0, 1.0),
          midInner: (z.midInner * k).clamp(0.0, 1.0),
          midOuter: (z.midOuter * k).clamp(0.0, 1.0),
          heel: (z.heel * k).clamp(0.0, 1.0),
        );
    return (n(f.left), n(f.right));
  }

  // ── analysis ───────────────────────────────────────────────────────────────

  static SessionAnalytics analyse(RecordedSession s) {
    // Knee interior angle per frame, both sides.
    final tR = <(int, double)>[], tL = <(int, double)>[];
    for (final f in s.frames) {
      final sk = f.skeleton;
      void add(List<(int, double)> out, String side) {
        final hip = sk['hip$side'], knee = sk['knee$side'], ankle = sk['ankle$side'];
        if (hip != null && knee != null && ankle != null) {
          out.add((f.tMs, jointAngleDeg(hip, knee, ankle)));
        }
      }

      add(tR, 'R');
      add(tL, 'L');
    }

    double variance(List<(int, double)> xs) {
      if (xs.length < 2) return 0;
      final mean = xs.fold(0.0, (a, b) => a + b.$2) / xs.length;
      return xs.fold(0.0, (a, b) => a + (b.$2 - mean) * (b.$2 - mean)) / xs.length;
    }

    final side = variance(tL) > variance(tR) ? 'L' : 'R';
    final raw = side == 'L' ? tL : tR;
    final angles = _smooth(raw, window: 5);

    // FSR-derived series.
    final load = <(int, double)>[];
    final asym = <(int, double)>[];
    final scale = s.fsrScale <= 0 ? 1.0 : s.fsrScale;
    for (final f in s.fsr) {
      final l = f.left.sum / scale, r = f.right.sum / scale;
      load.add((f.tMs, ((l + r) / 8 * 100).clamp(0, 200).toDouble()));
      final tot = l + r;
      asym.add((f.tMs, tot < 1e-6 ? 0 : (l - r) / tot * 100));
    }

    final reps = _detectReps(angles);

    double meanOf(Iterable<double> xs) {
      final list = xs.toList();
      return list.isEmpty ? 0 : list.reduce((a, b) => a + b) / list.length;
    }

    return SessionAnalytics(
      activeSide: side,
      angleSeries: angles,
      loadSeries: load,
      asymmetrySeries: asym,
      reps: reps,
      meanRom: meanOf(reps.map((r) => r.rom)),
      bestRom: reps.isEmpty ? 0 : reps.map((r) => r.rom).reduce(max),
      meanRepDuration: meanOf(reps.map((r) => r.durationSec)),
      meanAsymmetry: meanOf(asym.map((a) => a.$2.abs())),
      meanSmoothness: meanOf(reps.map((r) => r.smoothness)),
    );
  }

  static List<(int, double)> _smooth(List<(int, double)> xs, {int window = 5}) {
    if (xs.length <= window) return xs;
    final out = <(int, double)>[];
    for (var i = 0; i < xs.length; i++) {
      final a = max(0, i - window ~/ 2);
      final b = min(xs.length - 1, i + window ~/ 2);
      var sum = 0.0;
      for (var j = a; j <= b; j++) {
        sum += xs[j].$2;
      }
      out.add((xs[i].$1, sum / (b - a + 1)));
    }
    return out;
  }

  /// Threshold-crossing rep detection: a rep is an excursion above the
  /// midpoint between the resting baseline (p10) and peak (p95) lasting at
  /// least 400 ms.
  static List<RepInfo> _detectReps(List<(int, double)> angles) {
    if (angles.length < 10) return const [];
    final sorted = angles.map((a) => a.$2).toList()..sort();
    double pct(double p) => sorted[(sorted.length * p).floor().clamp(0, sorted.length - 1)];
    final base = pct(0.10), peak = pct(0.95);
    if (peak - base < 10) return const []; // no meaningful movement

    final threshold = base + (peak - base) * 0.5;
    final reps = <RepInfo>[];
    var inRep = false;
    var startI = 0;

    for (var i = 0; i < angles.length; i++) {
      final above = angles[i].$2 > threshold;
      if (above && !inRep) {
        inRep = true;
        startI = i;
      } else if (!above && inRep) {
        inRep = false;
        final startMs = angles[startI].$1, endMs = angles[i].$1;
        if (endMs - startMs < 400) continue;
        var repPeak = -double.infinity;
        for (var j = startI; j < i; j++) {
          repPeak = max(repPeak, angles[j].$2);
        }
        reps.add(RepInfo(
          index: reps.length + 1,
          startMs: startMs,
          endMs: endMs,
          peakAngle: repPeak,
          rom: repPeak - base,
          smoothness: _smoothnessOf(angles.sublist(startI, i)),
        ));
      }
    }
    return reps;
  }

  /// Inverse of normalised mean absolute second derivative — 1.0 means a
  /// perfectly smooth movement, lower means jerky.
  static double _smoothnessOf(List<(int, double)> seg) {
    if (seg.length < 4) return 1;
    var jerk = 0.0;
    var n = 0;
    for (var i = 2; i < seg.length; i++) {
      jerk += (seg[i].$2 - 2 * seg[i - 1].$2 + seg[i - 2].$2).abs();
      n++;
    }
    final mean = jerk / max(1, n);
    return (1 / (1 + mean)).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
