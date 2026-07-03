import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../models/protocol.dart';
import 'app_settings.dart';
import 'protocol_runner.dart';
import 'signal_quality.dart';
import 'unity_connection_service.dart';

enum RunStage { idle, connecting, preparing, ready, recording, saving, done, error }

/// Orchestrates a LIVE protocol run against Unity:
///   connect → configure_session → start_session (preview) → [Begin] →
///   start_recording + run the block clock → stop_recording → on session_saved,
///   write markers.csv + protocol.json + run.json into the recorded folder.
///
/// One continuous recording per run; the block structure lives in the markers.
/// Marker timestamps use the run clock (≈ start_recording), which is adequate
/// for block-design epoching.
class ProtocolRunController extends ChangeNotifier {
  final UnityConnectionService conn;
  final AppSettings settings;
  final Protocol protocol;
  final String participantId;
  final ProtocolRunner runner = ProtocolRunner();

  RunStage stage = RunStage.idle;
  String message = '';
  String? savedFolder;
  int? seed;

  /// Flutter-run-clock minus Unity-record-clock, in ms (null until measured).
  /// Subtracted from marker times to align them to the recorded sensor
  /// timeline. See [_startClockSync] / [_onPong].
  int? clockOffsetMs;
  int? clockRttMs;
  int _bestRtt = 1 << 30;
  final Map<int, int> _pingSentAt = {}; // pingId → runner.elapsedMs at send
  int _pingSeq = 0;
  Timer? _pingTimer;

  // Crash-safe incremental marker log (reconciled into the session folder on
  // save, so a mid-run crash can't orphan the block structure).
  File? _partialMarkers;
  String? _pendingDir;

  DateTime? _saveBaseline;
  bool _connListening = false;
  bool _artifactsStarted = false;
  Timer? _prepTimer;

  ProtocolRunController({
    required this.conn,
    required this.settings,
    required this.protocol,
    required this.participantId,
  });

  void _set(RunStage s, [String msg = '']) {
    stage = s;
    message = msg;
    notifyListeners();
  }

  /// Connect (if needed), push config, and load the capture scene so the
  /// operator can position the participant before recording.
  Future<void> prepare() async {
    if (!conn.isConnected) {
      _set(RunStage.connecting, 'Connecting to Unity…');
      await conn.connect(settings.wsUri);
    }
    if (!conn.isConnected) {
      _set(RunStage.error,
          'Unity is not running. Start Unity (or use Rehearse for a no-hardware run).');
      return;
    }

    // A live run records real sensors — turn off the dashboard's mock overlay
    // so the participant screen shows Unity's real stream, not synthetic data.
    // (Mock-based visualisation is what Rehearse is for.)
    conn.setMocks(motion: false, fsr: false, eeg: false);

    _set(RunStage.preparing, 'Configuring session…');
    final baseToken =
        protocol.classes.isNotEmpty ? protocol.classes.first.baseToken : 'Motion';
    conn.configureSession({
      'patientId': participantId,
      'exerciseClass': baseToken,
      'mode': 'Exercise',
      'zed': protocol.sensorZed,
      'fsr': protocol.sensorFsr,
      'eeg': protocol.sensorEeg,
      'fsrConnType': settings.fsrConnType,
      'fsrUsbPort': settings.fsrUsbPort,
      'fsrUri': settings.fsrUri,
      'fsrApiKey': settings.fsrApiKey,
    });
    await Future.delayed(const Duration(milliseconds: 400));
    conn.startSession();
    if (!_connListening) {
      conn.addListener(_onConn);
      _connListening = true;
    }

    // Don't show Begin until the sensors actually warm up — Unity streams its
    // first real frame only after the ZED is ready. _onConn flips us to ready
    // when that arrives; the timer is a fallback if it never confirms.
    if (conn.receivingLive) {
      _toReady();
    } else {
      _set(RunStage.preparing, 'Warming up the camera… (up to ~20 s)');
      _prepTimer = Timer(const Duration(seconds: 25),
          () => _toReady(timedOut: true));
    }
  }

  void _toReady({bool timedOut = false}) {
    _prepTimer?.cancel();
    _prepTimer = null;
    if (stage == RunStage.ready || stage == RunStage.recording) return;
    _set(
        RunStage.ready,
        timedOut
            ? 'Camera didn’t confirm warm-up — you can Begin, but check the ZED if the view stays empty.'
            : 'Camera ready. Press Begin when the participant is ready.');
  }

  // ── pre-flight signal-quality gate ─────────────────────────────────────────

  /// Operator override — lets Begin proceed even when a sensor looks off.
  bool overrideQualityGate = false;

  void setOverrideGate(bool v) {
    if (overrideQualityGate == v) return;
    overrideQualityGate = v;
    notifyListeners();
  }

  /// Live assessment of the enabled sensors from the current Unity stream.
  /// Re-read on each rebuild (the participant screen rebuilds on every frame),
  /// so it always reflects the latest sensor_update.
  SignalReport get signalReport => assessSignalQuality(
        conn.state,
        zed: protocol.sensorZed,
        fsr: protocol.sensorFsr,
        eeg: protocol.sensorEeg,
      );

  /// Whether Begin may be pressed: warm-up done AND signals pass (or the
  /// operator has overridden the gate, or nothing is being checked).
  bool get canBegin {
    if (stage != RunStage.ready) return false;
    if (overrideQualityGate) return true;
    final r = signalReport;
    return !r.hasChecks || r.allOk;
  }

  /// Begin the continuous recording and start the block clock.
  void begin() {
    if (stage != RunStage.ready) return;
    conn.startRecording();
    seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    runner.addListener(_onRunner);
    // Persist markers to disk as they fire (crash-safe) — set the sink and open
    // the file BEFORE start() so the first 'instruction' marker is captured.
    _beginPartialMarkers();
    runner.onMarker = _appendMarker;
    runner.start(protocol, seed: seed);
    _writePartialRunMeta();
    _startClockSync();
    _set(RunStage.recording);
  }

  // ── crash-safe incremental markers (Fix: markers were a single point of
  //    failure — held in memory and written only on session_saved) ───────────

  void _beginPartialMarkers() {
    try {
      final sep = Platform.pathSeparator;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final base = '${settings.protocolsRoot}${sep}_pending';
      final dirPath = '$base$sep${_safeName(participantId)}_$ts';
      Directory(dirPath).createSync(recursive: true);
      final file = File('$dirPath${sep}markers.partial.csv');
      file.writeAsStringSync('${RunMarker.csvHeader}\n');
      _pendingDir = dirPath;
      _partialMarkers = file;
    } catch (e) {
      debugPrint('[ProtocolRun] partial markers init failed: $e');
      _partialMarkers = null;
      _pendingDir = null;
    }
  }

  void _appendMarker(RunMarker m) {
    final f = _partialMarkers;
    if (f == null) return;
    try {
      // Synchronous append + flush → durable even if the app dies mid-run.
      f.writeAsStringSync('${m.toCsvRow()}\n', mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('[ProtocolRun] marker append failed: $e');
    }
  }

  /// Sidecar written once at run start so a crashed run (no session_saved) can
  /// still be reconstructed from the `_pending` folder.
  void _writePartialRunMeta() {
    final d = _pendingDir;
    if (d == null) return;
    try {
      final sep = Platform.pathSeparator;
      final meta = {
        'participantId': participantId,
        'protocolId': protocol.id,
        'protocolTitle': protocol.title,
        'seed': seed,
        'sequence': [for (final id in runner.sequence) id],
        'startedUtc': DateTime.now().toUtc().toIso8601String(),
        'note': 'Partial recovery data — reconciled into the session folder on save.',
      };
      File('$d${sep}run.partial.json')
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(meta));
    } catch (e) {
      debugPrint('[ProtocolRun] partial run meta failed: $e');
    }
  }

  void _cleanupPending() {
    final d = _pendingDir;
    if (d == null) return;
    try {
      Directory(d).deleteSync(recursive: true);
    } catch (_) {}
    _pendingDir = null;
    _partialMarkers = null;
  }

  static String _safeName(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  // ── clock-sync handshake (Fix: markers were stamped on the Flutter run clock
  //    but sensors record on Unity's clock — measure the offset & correct) ────

  void _startClockSync() {
    conn.onPong = _onPong;
    _bestRtt = 1 << 30;
    clockOffsetMs = null;
    clockRttMs = null;
    _pingSentAt.clear();
    _pingSeq = 0;
    // Ping repeatedly over the first ~12 s and keep the offset from the
    // lowest-RTT reply (NTP-style). Unity's main thread is busiest right at
    // recording start (scene + first frames), which inflates RTT and biases the
    // estimate — so we sample well past that and stop early once a clean
    // (<15 ms) localhost round trip gives a trustworthy offset.
    var sent = 0;
    _pingTimer = Timer.periodic(const Duration(milliseconds: 400), (t) {
      if (sent >= 30 || stage != RunStage.recording) {
        t.cancel();
        return;
      }
      final id = ++_pingSeq;
      _pingSentAt[id] = runner.elapsedMs;
      conn.sendPing(id);
      sent++;
    });
  }

  void _onPong(int pingId, int unityRecMs) {
    if (unityRecMs < 0) return; // Unity wasn't recording yet — ignore
    final sentAt = _pingSentAt[pingId];
    if (sentAt == null) return;
    final rtt = runner.elapsedMs - sentAt;
    if (rtt < 0 || rtt >= _bestRtt) return;
    _bestRtt = rtt;
    clockRttMs = rtt;
    // At the instant Unity handled the ping its record clock read unityRecMs;
    // in the Flutter run clock that instant was ≈ sentAt + rtt/2. The offset is
    // how far the Flutter clock leads Unity's record clock.
    clockOffsetMs = (sentAt + rtt ~/ 2) - unityRecMs;
    // A clean localhost round trip means the offset is accurate — stop pinging.
    if (rtt < 15) {
      _pingTimer?.cancel();
      _pingTimer = null;
    }
  }

  void pause() => runner.pause();
  void resume() => runner.resume();
  void skip() => runner.skipBlock();

  /// Stop early — finishes the run, which stops recording and saves.
  void abort() => runner.stop();

  void _onRunner() {
    if (runner.isDone && stage == RunStage.recording) {
      _finish();
    }
  }

  void _finish() {
    runner.removeListener(_onRunner);
    _pingTimer?.cancel();
    conn.onPong = null;
    _saveBaseline = DateTime.now();
    conn.stopRecording();
    _set(RunStage.saving, 'Saving session…');
  }

  void _onConn() {
    // Warm-up complete → enable Begin.
    if (stage == RunStage.preparing && conn.receivingLive) {
      _toReady();
      return;
    }
    if (stage != RunStage.saving) return;
    final s = conn.lastSaved;
    if (s == null) return;
    if (_saveBaseline != null && s.receivedAt.isBefore(_saveBaseline!)) return;
    _writeArtifacts(s.folder);
  }

  Future<void> _writeArtifacts(String folder) async {
    if (_artifactsStarted) return; // handle the save once
    _artifactsStarted = true;
    _pingTimer?.cancel();
    _set(RunStage.saving, 'Writing protocol + markers…');
    try {
      final sep = Platform.pathSeparator;
      final dir = Directory(folder);
      if (!await dir.exists()) await dir.create(recursive: true);

      final offset = clockOffsetMs ?? 0;

      // markers.csv — t_ms corrected onto Unity's record clock when the offset
      // was measured; t_run_ms keeps the raw Flutter run-clock value.
      final sb = StringBuffer('${RunMarker.csvHeader}\n');
      for (final m in runner.markers) {
        sb.writeln(m.toCsvRow(offsetMs: offset));
      }
      await File('$folder${sep}markers.csv').writeAsString(sb.toString());

      await File('$folder${sep}protocol.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(protocol.toJson()));

      final run = {
        'participantId': participantId,
        'protocolId': protocol.id,
        'protocolTitle': protocol.title,
        'protocolVersion': protocol.version,
        'seed': seed,
        'orderMode': protocol.orderMode.token,
        'sequence': [
          for (final id in runner.sequence)
            {'classId': id, 'className': protocol.classById(id)?.name ?? ''}
        ],
        // Flutter↔Unity clock alignment (null offset = handshake didn't confirm,
        // marker times left on the raw Flutter run clock).
        'clockOffsetMs': clockOffsetMs,
        'clockRttMs': clockRttMs,
        'markerTimebase':
            clockOffsetMs != null ? 'unity_record_clock' : 'flutter_run_clock',
        'savedUtc': DateTime.now().toUtc().toIso8601String(),
      };
      await File('$folder${sep}run.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(run));

      savedFolder = folder;
      _cleanupPending(); // final markers are safely in the session folder now
      _set(RunStage.done, 'Saved to $folder');
    } catch (e) {
      _set(RunStage.error, 'Recording saved, but writing protocol files failed: $e');
    }
  }

  @override
  void dispose() {
    _prepTimer?.cancel();
    _pingTimer?.cancel();
    conn.onPong = null;
    runner.onMarker = null;
    // Leaving an active run — whether previewing, ready, or recording — ends the
    // Unity capture session so it isn't left running/recording in the background.
    // The _pending markers file is intentionally left in place as recovery data
    // if we bail out before the session was saved.
    if (stage == RunStage.preparing ||
        stage == RunStage.ready ||
        stage == RunStage.recording) {
      runner.removeListener(_onRunner);
      conn.stopRecording();
    }
    if (_connListening) conn.removeListener(_onConn);
    runner.dispose();
    super.dispose();
  }
}
