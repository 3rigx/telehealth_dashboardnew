import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/protocol.dart';
import '../models/telerehab_state.dart';
import 'rep_analysis.dart';

/// Phase of a single block. Every block is instruction → active → reset; a
/// researcher-triggered comfort [pause] can freeze the run between/within
/// blocks. [done] ends the run.
enum RunPhase { idle, instruction, active, reset, pause, done }

extension RunPhaseX on RunPhase {
  String get label => switch (this) {
        RunPhase.idle => 'Idle',
        RunPhase.instruction => 'Get ready',
        RunPhase.active => 'Active',
        RunPhase.reset => 'Reset',
        RunPhase.pause => 'Paused',
        RunPhase.done => 'Complete',
      };
}

/// One timestamped event in a run, written to `markers.csv`. [tMs] is elapsed
/// wall-time since the run started (≈ since start_recording), which keeps
/// running through comfort pauses so it stays aligned with the continuous
/// recording.
class RunMarker {
  final int tMs;
  final String event; // instruction | active | reset | pause | resume | end
  final int block; // 1-based block number
  final String classId;
  final String className;
  final String baseToken;

  const RunMarker({
    required this.tMs,
    required this.event,
    required this.block,
    required this.classId,
    required this.className,
    required this.baseToken,
  });

  Map<String, dynamic> toJson() => {
        'tMs': tMs,
        'event': event,
        'block': block,
        'classId': classId,
        'className': className,
        'baseToken': baseToken,
      };

  /// Header for markers.csv. `t_ms` is the best-available time (corrected to
  /// Unity's record clock when the offset was measured); `t_run_ms` always
  /// keeps the raw Flutter run-clock value for audit. Extra columns are
  /// appended at the end so older 6-column parsers stay valid.
  static const String csvHeader =
      't_ms,event,block,class_id,class_name,base_token,t_run_ms';

  /// One markers.csv row. [offsetMs] is subtracted from [tMs] to map the
  /// Flutter run clock onto Unity's record clock (0 when unmeasured, giving the
  /// raw value in both columns).
  String toCsvRow({int offsetMs = 0}) {
    final corrected = tMs - offsetMs;
    return '$corrected,$event,$block,'
        '${_csv(classId)},${_csv(className)},${_csv(baseToken)},$tMs';
  }

  /// Minimal CSV escaping for names that might contain commas/quotes/newlines.
  static String _csv(String s) =>
      (s.contains(',') || s.contains('"') || s.contains('\n'))
          ? '"${s.replaceAll('"', '""')}"'
          : s;
}

/// Active-phase windows for post-hoc analysis (e.g. rep recompute): each
/// `active` marker spans until the next marker. [offsetMs] shifts the times
/// onto the same clock as the recorded sensor samples (Unity's record clock).
List<({int startMs, int endMs, int block})> activeWindowsFromMarkers(
  List<RunMarker> markers, {
  int offsetMs = 0,
}) {
  final out = <({int startMs, int endMs, int block})>[];
  for (var i = 0; i < markers.length; i++) {
    if (markers[i].event != 'active') continue;
    final end = i + 1 < markers.length ? markers[i + 1].tMs : markers[i].tMs;
    out.add((
      startMs: markers[i].tMs - offsetMs,
      endMs: end - offsetMs,
      block: markers[i].block,
    ));
  }
  return out;
}

/// Drives a protocol run on the Flutter side: builds the block sequence, runs
/// the instruction/active/reset clock, and counts repetitions from the live
/// sensor stream. Phase 2 keeps this entirely local (rehearsal); Phase 3 wires
/// its phase transitions to Unity (start/stop recording + block markers).
class ProtocolRunner extends ChangeNotifier {
  Protocol? protocol;
  List<String> sequence = const [];
  int seed = 0;

  int blockIndex = 0;
  RunPhase phase = RunPhase.idle;
  RunPhase _resumePhase = RunPhase.instruction;
  double phaseElapsed = 0; // seconds
  int reps = 0; // reps in the current active block
  int _repsAccum = 0; // reps across completed blocks

  /// Timestamped event log for the run (written to markers.csv on a live run).
  final List<RunMarker> markers = [];
  final Stopwatch _watch = Stopwatch();

  /// Invoked synchronously as each marker is logged, so a live run can persist
  /// markers incrementally (crash-safe) instead of only at the end.
  void Function(RunMarker marker)? onMarker;

  Timer? _timer;

  // Rep detector (seated leg extension): hysteresis on the knee flexion angle.
  // Shared with the post-hoc recompute over the recorded file so the live
  // display and the canonical count use identical logic.
  final KneeRepCounter _repCounter = KneeRepCounter();

  // ── derived state ─────────────────────────────────────────────────────────

  bool get isRunning => phase != RunPhase.idle && phase != RunPhase.done;
  bool get isPaused => phase == RunPhase.pause;
  bool get isDone => phase == RunPhase.done;
  int get totalBlocks => sequence.length;
  int get blockNumber => blockIndex + 1;
  int get totalReps => _repsAccum + (phase == RunPhase.active ? reps : 0);

  /// Elapsed run time in ms on the same clock the markers use — lets the run
  /// controller timestamp the clock-offset ping/pong against the marker clock.
  int get elapsedMs => _watch.elapsed.inMilliseconds;

  String? get currentClassId =>
      (blockIndex >= 0 && blockIndex < sequence.length) ? sequence[blockIndex] : null;
  ProtocolClass? get currentClass => protocol?.classById(currentClassId ?? '');

  double get phaseTotal {
    final c = currentClass;
    if (c == null) return 0;
    return switch (phase) {
      RunPhase.instruction => c.instructionSec,
      RunPhase.active => c.activeSec,
      RunPhase.reset => c.resetSec,
      _ => 0,
    };
  }

  double get phaseRemaining => (phaseTotal - phaseElapsed).clamp(0, double.infinity);
  double get phaseProgress =>
      phaseTotal <= 0 ? 0 : (phaseElapsed / phaseTotal).clamp(0.0, 1.0);

  /// Overall progress across the whole run (0..1), counting completed blocks.
  double get overallProgress {
    if (sequence.isEmpty) return 0;
    final perBlock = 1.0 / sequence.length;
    final withinBlock = switch (phase) {
      RunPhase.instruction => 0.0,
      RunPhase.active => 0.5 * phaseProgress,
      RunPhase.reset => 0.5 + 0.5 * phaseProgress,
      RunPhase.done => 1.0,
      _ => 0.0,
    };
    return ((blockIndex + withinBlock) * perBlock).clamp(0.0, 1.0);
  }

  // ── control ───────────────────────────────────────────────────────────────

  void start(Protocol p, {int? seed}) {
    protocol = p;
    this.seed = seed ?? (DateTime.now().millisecondsSinceEpoch & 0x7fffffff);
    sequence = p.generateSequence(seed: this.seed);
    blockIndex = 0;
    reps = 0;
    _repsAccum = 0;
    _repCounter.reset();
    phaseElapsed = 0;
    markers.clear();
    _watch
      ..reset()
      ..start();
    phase = sequence.isEmpty ? RunPhase.done : RunPhase.instruction;
    _timer?.cancel();
    if (phase != RunPhase.done) {
      _mark('instruction');
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick(0.1));
    }
    notifyListeners();
  }

  void _mark(String event) {
    final c = currentClass;
    final m = RunMarker(
      tMs: _watch.elapsed.inMilliseconds,
      event: event,
      block: blockNumber,
      classId: currentClassId ?? '',
      className: c?.name ?? '',
      baseToken: c?.baseToken ?? '',
    );
    markers.add(m);
    onMarker?.call(m);
  }

  void pause() {
    if (isRunning && phase != RunPhase.pause) {
      _resumePhase = phase;
      phase = RunPhase.pause;
      _mark('pause');
      notifyListeners();
    }
  }

  void resume() {
    if (phase == RunPhase.pause) {
      phase = _resumePhase;
      _mark('resume');
      notifyListeners();
    }
  }

  void togglePause() => isPaused ? resume() : pause();

  /// Jump straight to the next block (or finish if on the last).
  void skipBlock() {
    if (phase == RunPhase.idle || phase == RunPhase.done) return;
    if (phase == RunPhase.active) _repsAccum += reps;
    if (blockIndex >= sequence.length - 1) {
      _finish();
    } else {
      blockIndex++;
      phase = RunPhase.instruction;
      phaseElapsed = 0;
      reps = 0;
      _repCounter.reset();
      _mark('instruction');
    }
    notifyListeners();
  }

  void stop() => _finish();

  void _finish() {
    _mark('end');
    _watch.stop();
    phase = RunPhase.done;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  // ── clock ─────────────────────────────────────────────────────────────────

  void _tick(double dt) {
    if (phase == RunPhase.pause || phase == RunPhase.done || phase == RunPhase.idle) {
      return;
    }
    phaseElapsed += dt;
    if (phaseElapsed >= phaseTotal) {
      _advance();
    }
    notifyListeners();
  }

  void _advance() {
    switch (phase) {
      case RunPhase.instruction:
        phase = RunPhase.active;
        phaseElapsed = 0;
        reps = 0;
        _repCounter.reset();
        _mark('active');
        break;
      case RunPhase.active:
        _repsAccum += reps;
        phase = RunPhase.reset;
        phaseElapsed = 0;
        _mark('reset');
        break;
      case RunPhase.reset:
        if (blockIndex >= sequence.length - 1) {
          _finish();
        } else {
          blockIndex++;
          phase = RunPhase.instruction;
          phaseElapsed = 0;
          _mark('instruction');
        }
        break;
      default:
        break;
    }
  }

  // ── rep counting from the live sensor stream ────────────────────────────────

  /// Called by the participant screen on each sensor update. Only counts during
  /// the active phase. Does not notify (the screen rebuilds on its own).
  void feedSensor(TelerehabState s) {
    if (phase != RunPhase.active) return;
    final angle = _kneeAngle(s);
    if (angle == null) return;
    _repCounter.feed(angle);
    reps = _repCounter.count;
  }

  double? _kneeAngle(TelerehabState s) {
    for (final j in s.jointAngles) {
      if (j.name.toLowerCase().contains('knee')) return j.angle;
    }
    return s.skeleton?.activeAngle;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
