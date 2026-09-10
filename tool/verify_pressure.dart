// Pressure-capture verification tool.
//
//   dart run tool/verify_pressure.dart --sim [--seconds 60]
//       Simulates the single-insole capture path with TRUE concurrency (an
//       isolate producer emitting at 100 Hz + a 5 Hz consumer drain), mirroring
//       FootPressureSource -> PressureRecorder.Tick -> FootPressureCsvWriter.
//       Proves the drain-all design keeps every sample, and — for contrast —
//       shows what the OLD drain-to-latest read layer would have kept.
//
//   dart run tool/verify_pressure.dart --file <path/to/fsr.csv>
//       Verifies a REAL recording: row count + median / p95 of the delta between
//       consecutive arduino_ms values. This is the acceptance check to run after
//       a 60 s hardware (or Mock) recording:
//         ~6000 rows, median delta ~10 ms.  Hundreds of rows = the fix isn't live.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

const int periodMs = 10; // 100 Hz
const int tickMs = 200;  // 5 Hz consumer drain (the dashboard broadcast tick)

Future<void> main(List<String> args) async {
  if (args.contains('--file')) {
    final i = args.indexOf('--file');
    if (i + 1 >= args.length) {
      stderr.writeln('--file needs a path'); exit(2);
    }
    analyzeCsv(File(args[i + 1]));
    return;
  }
  if (args.contains('--session')) {
    final i = args.indexOf('--session');
    if (i + 1 >= args.length) {
      stderr.writeln('--session needs a folder'); exit(2);
    }
    verifySession(Directory(args[i + 1]));
    return;
  }
  if (args.contains('--sim')) {
    final si = args.indexOf('--seconds');
    final seconds = (si >= 0 && si + 1 < args.length) ? int.parse(args[si + 1]) : 60;
    await simulate(seconds);
    return;
  }
  stdout.writeln('usage: dart run tool/verify_pressure.dart '
      '--sim [--seconds N] | --file <fsr.csv> | --session <session-folder>');
}

// ── Isolate producer: emits an arduino_ms every 10 ms of wall time ───────────
void _producer(SendPort sp) {
  final sw = Stopwatch()..start();
  var next = 0;
  Timer.periodic(const Duration(milliseconds: 1), (t) {
    final now = sw.elapsedMilliseconds;
    // Emit every sample due by now (catches up if the timer coalesces) so the
    // device-clock spacing stays a true 10 ms regardless of host scheduling.
    while (next <= now) { sp.send(next); next += periodMs; }
    if (now >= _simEndMs) { t.cancel(); sp.send(-1); }
  });
}

int _simEndMs = 60000;

Future<void> simulate(int seconds) async {
  _simEndMs = seconds * 1000;
  stdout.writeln('Simulating $seconds s of 100 Hz capture (isolate producer + ${1000 ~/ tickMs} Hz drain)...');

  final rp = ReceivePort();
  // The new design: consumer accumulates EVERYTHING it drains.
  final kept = <int>[];
  // The old design (drain-to-latest): only the newest sample per tick survives.
  final oldKept = <int>[];
  int? latest;
  final done = Completer<void>();

  // 5 Hz drain: in the real code PressureRecorder.Tick() empties the queue into
  // the session list. Here the isolate queue is the OS/event queue; we mark tick
  // boundaries to model the old "keep latest each tick" loss.
  final ticker = Timer.periodic(const Duration(milliseconds: tickMs), (_) {
    if (latest != null) { oldKept.add(latest!); latest = null; }
  });

  await Isolate.spawn(_producer, rp.sendPort);
  rp.listen((msg) {
    final ms = msg as int;
    if (ms < 0) {
      if (latest != null) oldKept.add(latest!);
      ticker.cancel();
      rp.close();
      done.complete();
      return;
    }
    kept.add(ms);   // new design keeps every sample
    latest = ms;    // old design would overwrite, keeping only the latest per tick
  });

  await done.future;

  // Write the new-design stream to a v2-shaped fsr.csv, then analyze it.
  final out = File('${Directory.systemTemp.path}/sim_fsr.csv');
  final sb = StringBuffer('timestamp_utc,arduino_ms,t_ms,toe,medial,lateral,heel\n');
  final first = kept.isEmpty ? 0 : kept.first;
  for (final ms in kept) {
    sb.writeln(',$ms,${ms - first},512,400,380,600');
  }
  await out.writeAsString(sb.toString());

  stdout.writeln('\n── new design (drain-all → fsr.csv) ──');
  analyzeCsv(out);
  stdout.writeln('\n── OLD design (drain-to-latest at ${1000 ~/ tickMs} Hz) for contrast ──');
  stdout.writeln('  rows kept: ${oldKept.length}  '
      '(${(100 * oldKept.length / kept.length).toStringAsFixed(1)}% of the stream — the rest was thrown away)');
}

// ── whole-session acceptance check (run this after a real recording) ─────────
void verifySession(Directory dir) {
  if (!dir.existsSync()) { stderr.writeln('not found: ${dir.path}'); exit(2); }
  final sep = Platform.pathSeparator;

  stdout.writeln('Session: ${dir.path}\n── fsr.csv ──');
  analyzeCsv(File('${dir.path}${sep}fsr.csv'));

  stdout.writeln('\n── pressure_markers.csv ──');
  final mf = File('${dir.path}${sep}pressure_markers.csv');
  if (!mf.existsSync()) {
    stdout.writeln('  MISSING — no markers were captured.');
  } else {
    final lines = mf.readAsLinesSync();
    var mark = 0, baseline = 0;
    for (var i = 1; i < lines.length; i++) {
      final c = lines[i].split(',');
      if (c.length < 2) continue;
      final kind = c[1].trim().toUpperCase();
      if (kind == 'MARK') mark++;
      if (kind == 'BASELINE') baseline++;
    }
    stdout.writeln('  MARK rows     : $mark');
    stdout.writeln('  BASELINE rows : $baseline');
    stdout.writeln('  VERDICT       : ${mark > 0 ? "PASS — block-boundary marks present" : "CHECK — only baseline/none; no block marks"}');
  }

  stdout.writeln('\n── session.json (fsr.baseline) ──');
  final sj = File('${dir.path}${sep}session.json');
  if (!sj.existsSync()) {
    stdout.writeln('  MISSING session.json');
  } else {
    try {
      final j = jsonDecode(sj.readAsStringSync()) as Map<String, dynamic>;
      final fsr = j['fsr'] as Map<String, dynamic>?;
      final base = fsr?['baseline'];
      final names = (fsr?['channelNames'] as List?)?.join(',') ?? 'toe,medial,lateral,heel';
      stdout.writeln('  schemaVersion : ${j['schemaVersion']}');
      stdout.writeln('  foot          : ${fsr?['foot']}   insoleCount: ${fsr?['insoleCount']}');
      if (base is List && base.length == 4) {
        stdout.writeln('  baseline      : $names = $base  @ ${fsr?['baselineArduinoMs']} ms');
        stdout.writeln('  VERDICT       : PASS — baseline present (raw values are zeroable)');
      } else {
        stdout.writeln('  baseline      : $base');
        stdout.writeln('  VERDICT       : CHECK — no 4-channel baseline in session.json');
      }
    } catch (e) {
      stdout.writeln('  parse error: $e');
    }
  }
}

// ── fsr.csv analyzer (real or simulated) ─────────────────────────────────────
void analyzeCsv(File f) {
  if (!f.existsSync()) { stderr.writeln('not found: ${f.path}'); exit(2); }
  final lines = f.readAsLinesSync();
  if (lines.length < 2) { stderr.writeln('no data rows'); return; }

  final header = lines.first.toLowerCase().split(',');
  final col = header.indexOf('arduino_ms');
  if (col < 0) {
    stderr.writeln('no arduino_ms column — is this a v2 single-insole fsr.csv?');
    return;
  }

  final ard = <int>[];
  for (var i = 1; i < lines.length; i++) {
    final c = lines[i].split(',');
    if (c.length <= col) continue;
    final v = int.tryParse(c[col].trim());
    if (v != null) ard.add(v);
  }

  final rows = ard.length;
  final deltas = <int>[for (var i = 1; i < ard.length; i++) ard[i] - ard[i - 1]]..sort();
  int pct(double p) => deltas.isEmpty ? 0 : deltas[(deltas.length * p).floor().clamp(0, deltas.length - 1)];
  final span = ard.isEmpty ? 0 : ard.last - ard.first;
  final rateHz = span > 0 ? (rows - 1) * 1000.0 / span : 0.0;

  stdout.writeln('  rows            : $rows');
  stdout.writeln('  arduino_ms span : $span ms  (~${(span / 1000).toStringAsFixed(1)} s)');
  stdout.writeln('  effective rate  : ${rateHz.toStringAsFixed(1)} Hz');
  stdout.writeln('  median delta    : ${pct(0.50)} ms');
  stdout.writeln('  p95 delta       : ${pct(0.95)} ms');
  stdout.writeln('  max delta       : ${deltas.isEmpty ? 0 : deltas.last} ms');
  final ok = rows > 3000 && pct(0.50) <= 12;
  stdout.writeln('  VERDICT         : ${ok ? "PASS — full-rate capture" : "CHECK — row count/rate below 100 Hz expectation"}');
}
