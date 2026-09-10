// Synthetic dashboard client that stress-/latency-tests the Unity WebSocket
// bridge (ws://localhost:8765) the same way the real dashboard talks to it.
//
// It measures the things that actually matter for this real-time capture app —
// broadcast throughput, inter-frame jitter (stalls), command round-trip latency,
// and payload size — and how they hold up over a long run and under multiple
// concurrent dashboard clients. It is the honest replacement for a "load test":
// there is no multi-user server here, so the meaningful load is (a) endurance
// and (b) how the one bridge behaves broadcasting to N connected clients.
//
// Pure Dart (dart:io WebSocket) — no Flutter, no extra packages. Run with:
//
//   dart run tool/ws_perf_test.dart --seconds 60
//       Passive: measure whatever Unity is already broadcasting (drive the
//       session yourself from the dashboard, or from Unity).
//
//   dart run tool/ws_perf_test.dart --drive --seconds 120
//       Bring Unity into the capture scene itself (configure_session +
//       start_session) so broadcasts flow during PREVIEW — no recording, no
//       files, no hardware needed (skeleton is simply absent with no camera).
//
//   dart run tool/ws_perf_test.dart --drive --record --seconds 1800 --clients 3
//       30-min soak that also records (exercises file I/O), with 3 concurrent
//       clients as broadcast load. Writes a real session — use a throwaway id.
//
// A per-second CSV is written to --out (default ./perf_<timestamp>.csv) and a
// summary is printed at the end. NOTE: EEG frame-drop counts are internal to
// Unity and not broadcast, so assess those from the saved eeg.csv / Player.log,
// not from this tool. This tool measures the bridge + broadcast pipeline.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _defaultUri = 'ws://localhost:8765';

void main(List<String> args) async {
  final opts = _Opts.parse(args);
  if (opts.help) {
    stdout.write(_usage);
    return;
  }

  stdout.writeln('WS perf test → ${opts.uri}');
  stdout.writeln('  duration=${opts.seconds}s  clients=${opts.clients}  '
      'ping=${opts.pingMs}ms  drive=${opts.drive}  record=${opts.record}');
  stdout.writeln('  out=${opts.outPath}');

  // Client 0 is the MEASURED client (rate/jitter/RTT). Extra clients are pure
  // broadcast load — each is a full extra subscriber Unity must fan out to.
  final clients = <_Client>[];
  for (var i = 0; i < opts.clients; i++) {
    final c = _Client(i, opts);
    try {
      await c.connect();
    } catch (e) {
      stderr.writeln('Client $i could not connect: $e\n'
          'Is Unity running with the bridge up? (ws server logs '
          '"[TelerehabWS] Server started")');
      for (final done in clients) {
        await done.close();
      }
      exit(1);
    }
    clients.add(c);
  }
  final primary = clients.first;

  // Optionally drive Unity into a streaming state so there is something to
  // measure. Only the primary client sends commands.
  if (opts.drive) {
    stdout.writeln('Driving: configure_session + start_session…');
    primary.send({
      'type': 'command',
      'action': 'configure_session',
      // Hardware-free: mock FSR, no EEG, ZED on (no body → skeleton omitted,
      // but sensor_update still ticks at the full broadcast rate).
      'patientId': opts.patientId,
      'exerciseClass': 'Motion',
      'mode': 'Exercise',
      'zed': true,
      'fsr': false,
      'eeg': false,
      'fsrConnType': 'Mock',
    });
    await Future.delayed(const Duration(milliseconds: 400));
    primary.send({'type': 'command', 'action': 'start_session'});

    // If Unity was already streaming (re-driving a session), the old scene's
    // stream keeps draining for a moment while the new scene loads. Settle past
    // that, then re-arm so we measure the RELOADED stream, not the stale one.
    await Future.delayed(const Duration(seconds: 2));
    for (final c in clients) {
      c.rearmFirstFrame();
    }
  }

  // Wait for the first sensor_update so warm-up (scene load) doesn't pollute the
  // measured window. In passive mode this just waits for the existing stream.
  stdout.writeln('Waiting for first sensor_update…');
  final warmMs = await primary.waitForFirstFrame(
      timeout: Duration(seconds: opts.drive ? 40 : 20));
  if (warmMs == null) {
    stderr.writeln('No sensor_update within timeout.\n'
        '  • Passive mode: start a session from the dashboard first.\n'
        '  • --drive: works best against Unity sitting at the MENU. Re-driving a\n'
        '    session while already in the capture scene reloads it and can hang\n'
        '    sensor re-init (esp. the ZED with no camera) — return to the menu or\n'
        '    restart the build, then retry.');
    for (final c in clients) {
      await c.close();
    }
    exit(2);
  }
  stdout.writeln('First frame after $warmMs ms — starting measurement.');

  if (opts.record) {
    stdout.writeln('Recording: start_recording (writes a session)…');
    primary.send({'type': 'command', 'action': 'start_recording'});
  }

  // Measurement window: reset every client's counters, then sample per second.
  for (final c in clients) {
    c.resetWindow();
  }

  final out = File(opts.outPath).openWrite();
  out.writeln('elapsed_s,rate_hz,interarrival_mean_ms,interarrival_p95_ms,'
      'interarrival_max_ms,rtt_last_ms,bytes_mean');

  final started = DateTime.now();
  var nextPingId = 1;
  final allRtts = <int>[];
  final allRates = <double>[];
  final allP95 = <double>[];
  var maxGapOverall = 0.0;

  final ticker = Completer<void>();
  var elapsed = 0;
  Timer? pinger;
  if (opts.pingMs > 0) {
    pinger = Timer.periodic(Duration(milliseconds: opts.pingMs), (_) {
      final id = nextPingId++;
      primary.markPing(id);
      primary.send({'type': 'command', 'action': 'ping', 'pingId': id});
    });
  }

  final secondly = Timer.periodic(const Duration(seconds: 1), (t) {
    elapsed++;
    final w = primary.takeWindow(); // 1-second stats for the measured client
    allRates.add(w.rateHz);
    if (w.p95Ms > 0) allP95.add(w.p95Ms);
    if (w.maxMs > maxGapOverall) maxGapOverall = w.maxMs;
    final rtt = primary.lastRttMs;
    if (rtt != null) allRtts.add(rtt);

    out.writeln('$elapsed,${w.rateHz.toStringAsFixed(2)},'
        '${w.meanMs.toStringAsFixed(2)},${w.p95Ms.toStringAsFixed(2)},'
        '${w.maxMs.toStringAsFixed(2)},${rtt ?? ''},'
        '${w.bytesMean.toStringAsFixed(0)}');

    // Live one-line status so a long soak shows progress.
    stdout.write('\r  t=${elapsed}s  rate=${w.rateHz.toStringAsFixed(1)}Hz  '
        'jitter_p95=${w.p95Ms.toStringAsFixed(0)}ms  '
        'max_gap=${w.maxMs.toStringAsFixed(0)}ms  '
        'rtt=${rtt ?? '-'}ms      ');

    if (elapsed >= opts.seconds) {
      t.cancel();
      ticker.complete();
    }
  });

  await ticker.future;
  secondly.cancel();
  pinger?.cancel();

  if (opts.record) {
    stdout.writeln('\nStopping recording…');
    primary.send({'type': 'command', 'action': 'stop_recording'});
    await Future.delayed(const Duration(seconds: 2)); // let it save
  }

  await out.flush();
  await out.close();
  for (final c in clients) {
    await c.close();
  }

  // ── summary ────────────────────────────────────────────────────────────────
  final wall = DateTime.now().difference(started).inMilliseconds / 1000.0;
  stdout.writeln('\n\n──────── SUMMARY ────────');
  stdout.writeln('Wall time measured : ${wall.toStringAsFixed(1)} s');
  stdout.writeln('Warm-up (first frame): $warmMs ms');
  stdout.writeln('Broadcast rate (Hz): '
      'mean ${_mean(allRates).toStringAsFixed(2)} · '
      'min ${(allRates.isEmpty ? 0 : allRates.reduce(min)).toStringAsFixed(2)} · '
      'max ${(allRates.isEmpty ? 0 : allRates.reduce(max)).toStringAsFixed(2)}');
  stdout.writeln('Inter-arrival p95 (ms): '
      'median-of-seconds ${_pct(allP95, 50).toStringAsFixed(1)} · '
      'worst-second ${(allP95.isEmpty ? 0 : allP95.reduce(max)).toStringAsFixed(1)}');
  stdout.writeln('Worst single stall  : ${maxGapOverall.toStringAsFixed(1)} ms');
  if (allRtts.isNotEmpty) {
    stdout.writeln('Command RTT (ms)   : '
        'median ${_pct(allRtts.map((e) => e.toDouble()).toList(), 50).toStringAsFixed(1)} · '
        'p95 ${_pct(allRtts.map((e) => e.toDouble()).toList(), 95).toStringAsFixed(1)} · '
        'max ${allRtts.reduce(max)}');
  }
  stdout.writeln('Payload size (bytes): mean ${primary.lifetimeBytesMean.toStringAsFixed(0)}');
  stdout.writeln('Clients (load)     : ${opts.clients}');
  stdout.writeln('CSV                : ${opts.outPath}');
  stdout.writeln('\nRate should sit near Unity\'s configured broadcast rate '
      '(1 / _updateInterval). A rate that sags below that, a rising p95, or big '
      'max-gaps under load or over time are the signals to chase.');
}

// ── one synthetic dashboard client ─────────────────────────────────────────────

class _Client {
  final int id;
  final _Opts opts;
  WebSocket? _ws;

  _Client(this.id, this.opts);

  // First-frame detection. Re-armable so --drive can discard any stale frames
  // from a previous session's stream and only latch onto the post-reload one.
  Completer<int> _firstFrame = Completer<int>();
  final _stopwatch = Stopwatch()..start();

  // Current 1-second window (measured client only, but cheap for all).
  int _winCount = 0;
  double _winBytes = 0;
  double? _lastArrivalMs;
  final List<double> _winGaps = [];

  // Lifetime bytes.
  double _lifeBytes = 0;
  int _lifeCount = 0;

  // Ping bookkeeping.
  final Map<int, int> _pingSentMs = {};
  int? lastRttMs;

  Future<void> connect() async {
    _ws = await WebSocket.connect(opts.uri);
    _ws!.listen(_onData, onError: (_) {}, cancelOnError: false);
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    final nowMs = _stopwatch.elapsedMicroseconds / 1000.0;
    // Cheap type sniff before a full decode — the hot path is sensor_update.
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'sensor_update':
        if (!_firstFrame.isCompleted) {
          _firstFrame.complete(_stopwatch.elapsedMilliseconds);
        }
        _winCount++;
        _lifeCount++;
        _winBytes += raw.length;
        _lifeBytes += raw.length;
        if (_lastArrivalMs != null) _winGaps.add(nowMs - _lastArrivalMs!);
        _lastArrivalMs = nowMs;
        break;
      case 'pong':
        final pid = (m['pingId'] as num?)?.toInt();
        if (pid != null) {
          final sent = _pingSentMs.remove(pid);
          if (sent != null) lastRttMs = _stopwatch.elapsedMilliseconds - sent;
        }
        break;
    }
  }

  Future<int?> waitForFirstFrame({required Duration timeout}) {
    return _firstFrame.future.timeout(timeout, onTimeout: () => -1).then(
        (v) => v < 0 ? null : v);
  }

  /// Discard any frame seen so far and wait fresh for the next one. Used after
  /// start_session so measurement latches onto the reloaded scene, not the
  /// previous session's still-draining stream.
  void rearmFirstFrame() => _firstFrame = Completer<int>();

  void markPing(int id) => _pingSentMs[id] = _stopwatch.elapsedMilliseconds;

  void resetWindow() {
    _winCount = 0;
    _winBytes = 0;
    _winGaps.clear();
    _lastArrivalMs = null;
    _lifeBytes = 0;
    _lifeCount = 0;
  }

  _Window takeWindow() {
    final gaps = List<double>.from(_winGaps);
    final w = _Window(
      rateHz: _winCount.toDouble(),
      meanMs: _mean(gaps),
      p95Ms: _pct(gaps, 95),
      maxMs: gaps.isEmpty ? 0 : gaps.reduce(max),
      bytesMean: _winCount == 0 ? 0 : _winBytes / _winCount,
    );
    _winCount = 0;
    _winBytes = 0;
    _winGaps.clear();
    return w;
  }

  double get lifetimeBytesMean => _lifeCount == 0 ? 0 : _lifeBytes / _lifeCount;

  void send(Map<String, dynamic> msg) => _ws?.add(jsonEncode(msg));

  Future<void> close() async {
    try {
      await _ws?.close();
    } catch (_) {}
  }
}

class _Window {
  final double rateHz;
  final double meanMs;
  final double p95Ms;
  final double maxMs;
  final double bytesMean;
  _Window({
    required this.rateHz,
    required this.meanMs,
    required this.p95Ms,
    required this.maxMs,
    required this.bytesMean,
  });
}

// ── options ─────────────────────────────────────────────────────────────────

class _Opts {
  final String uri;
  final int seconds;
  final int clients;
  final int pingMs;
  final bool drive;
  final bool record;
  final String patientId;
  final String outPath;
  final bool help;

  _Opts({
    required this.uri,
    required this.seconds,
    required this.clients,
    required this.pingMs,
    required this.drive,
    required this.record,
    required this.patientId,
    required this.outPath,
    required this.help,
  });

  static _Opts parse(List<String> a) {
    String get(String k, String d) {
      final i = a.indexOf(k);
      return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
    }

    bool flag(String k) => a.contains(k);

    final record = flag('--record');
    final ts = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    return _Opts(
      uri: get('--uri', _defaultUri),
      seconds: int.tryParse(get('--seconds', '60')) ?? 60,
      clients: max(1, int.tryParse(get('--clients', '1')) ?? 1),
      pingMs: int.tryParse(get('--ping-ms', '500')) ?? 500,
      drive: flag('--drive') || record, // recording implies driving
      record: record,
      patientId: get('--patient', 'PERF-TEST'),
      outPath: get('--out', 'perf_$ts.csv'),
      help: flag('-h') || flag('--help'),
    );
  }
}

const _usage = '''
ws_perf_test — Unity WebSocket bridge throughput/latency harness

  dart run tool/ws_perf_test.dart [options]

Options
  --uri <ws://…>     Bridge URI              (default ws://localhost:8765)
  --seconds <n>      Measurement duration    (default 60)
  --clients <n>      Concurrent subscribers  (default 1; extras = broadcast load)
  --ping-ms <n>      Command-RTT ping period (default 500; 0 disables)
  --drive            Send configure+start_session so broadcasts flow (no HW)
  --record           Also start_recording (writes a session); implies --drive
  --patient <id>     patientId when driving   (default PERF-TEST)
  --out <path>       Per-second CSV           (default perf_<timestamp>.csv)
  -h, --help         This help

Modes
  Passive  : start a session from the dashboard, then run without --drive.
  Driven   : --drive        → preview-rate throughput, no files, no hardware.
  Soak     : --drive --record --seconds 1800  → endurance incl. file I/O.
  Load     : --clients 5    → fan-out cost of many dashboards on one bridge.
''';

// ── small stats helpers ─────────────────────────────────────────────────────

double _mean(List<double> xs) =>
    xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

double _pct(List<double> xs, num p) {
  if (xs.isEmpty) return 0;
  final s = List<double>.from(xs)..sort();
  final idx = ((p / 100.0) * (s.length - 1)).round().clamp(0, s.length - 1);
  return s[idx];
}
