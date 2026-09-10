import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import '../models/pressure_config.dart';
import '../models/protocol.dart';
import '../models/session_models.dart';
import '../models/skeleton_3d.dart';
import '../models/telerehab_state.dart';
import 'mock_sensors.dart';

/// Reads the session library that the Unity build writes to disk:
///   `<sessionsRoot>/<PatientId>/<timestamp>_<Class>/{session.json, fsr.csv, zed_skeleton.json}`
class SessionRepository extends ChangeNotifier {
  String _root = '';
  List<String> patients = [];
  final Map<String, List<SessionSummary>> _sessionsByPatient = {};

  String get root => _root;

  void setRoot(String root) {
    if (root == _root) return;
    _root = root;
    refresh();
  }

  Future<void> refresh() async {
    patients = [];
    _sessionsByPatient.clear();
    try {
      final dir = Directory(_root);
      if (await dir.exists()) {
        patients = dir
            .listSync()
            .whereType<Directory>()
            .map((d) => d.path.split(Platform.pathSeparator).last)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      }
    } catch (_) {}
    notifyListeners();
  }

  List<SessionSummary> sessionsFor(String patientId) =>
      _sessionsByPatient[patientId] ?? const [];

  Future<List<SessionSummary>> loadSessions(String patientId) async {
    final out = <SessionSummary>[];
    try {
      final dir = Directory('$_root${Platform.pathSeparator}$patientId');
      if (await dir.exists()) {
        for (final d in dir.listSync().whereType<Directory>()) {
          final sessionId = d.path.split(Platform.pathSeparator).last;
          var manifest = const RecordedManifest();
          final mf = File('${d.path}${Platform.pathSeparator}session.json');
          if (await mf.exists()) {
            try {
              manifest = RecordedManifest.fromJson(
                  jsonDecode(await mf.readAsString()) as Map<String, dynamic>);
            } catch (_) {}
          }
          out.add(SessionSummary(
            patientId: patientId,
            sessionId: sessionId,
            folderPath: d.path,
            manifest: manifest,
          ));
        }
      }
    } catch (_) {}
    out.sort((a, b) => (b.startedAt ?? DateTime(0))
        .compareTo(a.startedAt ?? DateTime(0))); // newest first
    _sessionsByPatient[patientId] = out;
    notifyListeners();
    return out;
  }

  /// Next 1-based trial number for patient + class (mirrors Unity's
  /// SessionPaths.NextTrialNumber so the dashboard can show it up front).
  int nextTrialNumber(String patientId, String classToken) {
    final sessions = _sessionsByPatient[patientId];
    if (sessions == null) return 1;
    return sessions.where((s) => s.sessionId.endsWith('_$classToken')).length + 1;
  }

  /// Load the full sensor data of one session for replay.
  Future<RecordedSession> loadSession(SessionSummary summary) async {
    final sep = Platform.pathSeparator;

    // Frames/rows are collected with their raw on-disk t_ms first, then the
    // timeline is rebuilt (see [_cumulativeTimeline]) because Unity writes
    // t_ms as the per-frame delta (ms since the previous state), not the time
    // since session start.
    final rawSkeletons = <(int, Skeleton3D)>[];
    final rawFsr = <(int, FootZones, FootZones)>[];

    // ---- zed_skeleton.json ----
    try {
      final f = File('${summary.folderPath}${sep}zed_skeleton.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final bodyFormat = j['bodyFormat'] ?? summary.manifest.bodyFormat;
        for (final fr in (j['frames'] as List? ?? const [])) {
          if (fr is! Map<String, dynamic>) continue;
          final sk = fr['skeleton'];
          if (sk is! Map<String, dynamic>) continue;
          final skeleton = skeletonFromUnityJson(sk, bodyFormat);
          if (skeleton != null) {
            rawSkeletons.add((fr['tMs'] ?? 0, skeleton));
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to parse zed_skeleton.json: $e');
    }

    // ---- fsr.csv ----
    // Self-describing: the header tells the layout so both eras open regardless of
    // the manifest. v2 (single insole) = "timestamp_utc,arduino_ms,t_ms,toe,medial,
    // lateral,heel" with an ALREADY-ABSOLUTE t_ms; v1 (legacy two insoles) =
    // "...,L_toe,...,R_heel" with a per-row DELTA t_ms.
    var fsrAbsolute = false;
    final recordFoot = summary.manifest.fsr.foot.isEmpty
        ? PressureConfig.foot
        : summary.manifest.fsr.foot;
    try {
      final f = File('${summary.folderPath}${sep}fsr.csv');
      if (await f.exists()) {
        final lines = await f.readAsLines();
        final header = lines.isNotEmpty ? lines.first.toLowerCase() : '';
        final singleFoot = header.contains('arduino_ms') || !header.contains('l_toe');
        double p(String s) => double.tryParse(s) ?? 0;

        for (var i = 1; i < lines.length; i++) {
          final c = lines[i].split(',');
          if (singleFoot) {
            // timestamp_utc, arduino_ms, t_ms, toe, medial, lateral, heel
            if (c.length < 7) continue;
            fsrAbsolute = true;
            final zones = FootZones(toe: p(c[3]), medial: p(c[4]), lateral: p(c[5]), heel: p(c[6]));
            final empty = const FootZones();
            rawFsr.add((
              int.tryParse(c[2]) ?? 0, // t_ms, absolute
              PressureConfig.isLeft(recordFoot) ? zones : empty,
              PressureConfig.isLeft(recordFoot) ? empty : zones,
            ));
          } else {
            // Legacy two-insole: timestamp_utc, t_ms(delta), L_*(4), R_*(4)
            if (c.length < 10) continue;
            rawFsr.add((
              int.tryParse(c[1]) ?? 0,
              FootZones(toe: p(c[2]), medial: p(c[3]), lateral: p(c[4]), heel: p(c[5])),
              FootZones(toe: p(c[6]), medial: p(c[7]), lateral: p(c[8]), heel: p(c[9])),
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to parse fsr.csv: $e');
    }

    // ---- eeg.csv (counter,t_ms,ch1..ch8) — parallel high-rate stream ----
    final eeg = <EegFrame>[];
    try {
      final f = File('${summary.folderPath}${sep}eeg.csv');
      if (await f.exists()) {
        final lines = await f.readAsLines();
        for (var i = 1; i < lines.length; i++) {
          final c = lines[i].split(',');
          if (c.length < 10) continue;
          eeg.add(EegFrame(
            tMs: int.tryParse(c[1]) ?? 0,
            channels: [for (var k = 2; k < 10; k++) double.tryParse(c[k]) ?? 0],
          ));
        }
      }
    } catch (e) {
      debugPrint('Failed to parse eeg.csv: $e');
    }

    // ---- markers.csv (protocol block/phase events — already absolute ms) ----
    final markers = <SessionMarker>[];
    try {
      final f = File('${summary.folderPath}${sep}markers.csv');
      if (await f.exists()) {
        final lines = await f.readAsLines();
        for (var i = 1; i < lines.length; i++) {
          final m = SessionMarker.tryParseCsv(lines[i]);
          if (m != null) markers.add(m);
        }
      }
    } catch (e) {
      debugPrint('Failed to parse markers.csv: $e');
    }

    // ---- protocol.json snapshot (class id → theme colour for the timeline) ----
    final classColors = <String, int>{};
    try {
      final f = File('${summary.folderPath}${sep}protocol.json');
      if (await f.exists()) {
        final p = Protocol.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>);
        for (final c in p.classes) {
          classColors[c.id] = c.colorValue;
        }
      }
    } catch (e) {
      debugPrint('Failed to parse protocol.json: $e');
    }

    final frameTimes = cumulativeTimeline([for (final r in rawSkeletons) r.$1]);
    // v2 single-foot rows carry an already-absolute t_ms (Arduino clock), so pass
    // them through unchanged; v1 rows are per-frame deltas needing accumulation.
    final fsrTimes = fsrAbsolute
        ? [for (final r in rawFsr) r.$1]
        : cumulativeTimeline([for (final r in rawFsr) r.$1]);

    final frames = [
      for (var i = 0; i < rawSkeletons.length; i++)
        SkeletonFrame(tMs: frameTimes[i], skeleton: rawSkeletons[i].$2),
    ];
    final fsr = [
      for (var i = 0; i < rawFsr.length; i++)
        FsrSample(tMs: fsrTimes[i], left: rawFsr[i].$2, right: rawFsr[i].$3),
    ];

    return RecordedSession(
      summary: summary,
      frames: frames,
      fsr: fsr,
      eeg: eeg,
      markers: markers,
      classColors: classColors,
    );
  }

  /// Bundle an entire recorded session folder into a `.zip` at [outZipPath].
  /// Includes everything in the folder (sensor CSVs, skeleton JSON, manifest,
  /// and the protocol/markers/run files written for protocol runs).
  Future<String> exportSessionZip(String folderPath, String outZipPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      throw StateError('Session folder not found: $folderPath');
    }
    final archive = Archive();
    final base = dir.path;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final bytes = await entity.readAsBytes();
      var rel = entity.path.substring(base.length).replaceAll('\\', '/');
      if (rel.startsWith('/')) rel = rel.substring(1);
      archive.addFile(ArchiveFile(rel, bytes.length, bytes));
    }
    final data = ZipEncoder().encode(archive);
    if (data == null) throw StateError('Failed to encode zip');
    await File(outZipPath).writeAsBytes(data);
    return outZipPath;
  }

  /// Synthesised 90-second knee-extension session for testing replay without
  /// any recorded data.
  RecordedSession mockSession() => MockSensors.buildMockSession();
}

/// Builds a monotonic playback timeline from on-disk `t_ms` values.
///
/// Unity records `t_ms` as the elapsed time since the *previous* sample, so a
/// raw stream looks like `[50, 50, 49, …]` — accumulating it yields the real
/// timeline. If a file is ever written with already-cumulative timestamps
/// (strictly increasing, spanning more than one frame) it is used verbatim, so
/// this stays correct if the writer is changed later. Shared by the replay
/// loader and the post-hoc rep recompute so both reconstruct the same clock.
List<int> cumulativeTimeline(List<int> raw) {
  if (raw.length < 2) return raw;
  var increasing = true;
  for (var i = 1; i < raw.length; i++) {
    if (raw[i] <= raw[i - 1]) {
      increasing = false;
      break;
    }
  }
  if (increasing && raw.last - raw.first > raw.length) return raw;
  final out = <int>[];
  var acc = 0;
  for (final d in raw) {
    acc += d > 0 ? d : 0;
    out.add(acc);
  }
  return out;
}
