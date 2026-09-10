import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import '../models/participant.dart';

/// Builds a de-identified export bundle (zip) of one participant's recorded
/// data, safe to share with collaborators / attach to an analysis pipeline:
///
///  • participant code optionally re-aliased (e.g. P-003 → EXP-01) so the
///    export can't be linked back to the study registry if it circulates
///  • calendar dates removed everywhere — session folders and JSON timestamps
///    become study days ("day004") relative to enrolment (HIPAA safe-harbor:
///    dates are identifiers; elapsed days are not)
///  • free-text `notes` fields stripped from every JSON file
///  • raw signal files (CSV / skeleton frames) copied as-is — they only
///    contain relative milliseconds
///  • a manifest + README data dictionary included
class DeidentifiedExport {
  final Participant participant;
  final String sessionsRoot;

  /// When non-null, every occurrence of the participant code in file names and
  /// JSON string values is replaced with this alias.
  final String? alias;

  DeidentifiedExport({
    required this.participant,
    required this.sessionsRoot,
    this.alias,
  });

  String get _outId => alias ?? participant.code;

  static final _isoRe =
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})?$');
  static final _folderTsRe = RegExp(r'(\d{4})-?(\d{2})-?(\d{2})[T_\-]?(\d{2})-?(\d{2})-?(\d{2})?');

  /// Days since enrolment (00:00 local of the enrolment day = day 0).
  int _studyDay(DateTime t) {
    final d0 = DateTime(participant.enrolledUtc.toLocal().year,
        participant.enrolledUtc.toLocal().month, participant.enrolledUtc.toLocal().day);
    final tl = t.toLocal();
    return DateTime(tl.year, tl.month, tl.day).difference(d0).inDays;
  }

  String _dayTag(DateTime t) {
    final d = _studyDay(t);
    return 'day${(d < 0 ? 0 : d).toString().padLeft(3, '0')}';
  }

  /// Writes the zip to [outPath]. Returns the number of files bundled.
  Future<int> run(String outPath) async {
    final srcDir =
        Directory('$sessionsRoot${Platform.pathSeparator}${participant.code}');
    if (!srcDir.existsSync()) {
      throw const FileSystemException('No recorded data for this participant');
    }

    final archive = Archive();
    var fileCount = 0;
    final sessionDirs = srcDir
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final sessionIndex = <Map<String, dynamic>>[];
    var seq = 0;
    for (final dir in sessionDirs) {
      seq++;
      final rawName = dir.path.split(Platform.pathSeparator).last;
      final outFolder = _deidentifyFolderName(rawName, seq);
      sessionIndex.add({'folder': outFolder, 'files': <String>[]});

      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        final rel = f.path
            .substring(dir.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        List<int> bytes;
        if (rel.toLowerCase().endsWith('.json')) {
          bytes = utf8.encode(_scrubJson(await f.readAsString()));
        } else {
          bytes = await f.readAsBytes();
        }
        archive.addFile(ArchiveFile('$_outId/$outFolder/$rel', bytes.length, bytes));
        (sessionIndex.last['files'] as List).add(rel);
        fileCount++;
      }
    }

    // manifest + data dictionary
    final manifest = const JsonEncoder.withIndent('  ').convert({
      'schema': 'telerehab.deidentified-export.v1',
      'participant': _outId,
      'realiased': alias != null,
      'consentVersion': participant.consentVersion,
      'status': participant.status.token,
      // Structured demographic — not an identifier; kept for analysis
      // (free-text notes, by contrast, are stripped).
      'gender': participant.gender.token,
      'dateConvention':
          'All calendar dates replaced by study days (dayNNN = days since enrolment). '
              'Times of day preserved. In-file sample times are relative milliseconds.',
      'sessions': sessionIndex,
    });
    final manifestBytes = utf8.encode(manifest);
    archive.addFile(
        ArchiveFile('$_outId/manifest.json', manifestBytes.length, manifestBytes));

    final readmeBytes = utf8.encode(_readme());
    archive.addFile(ArchiveFile('$_outId/README.txt', readmeBytes.length, readmeBytes));

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) throw Exception('Zip encoding failed');
    await File(outPath).writeAsBytes(zipData, flush: true);
    return fileCount;
  }

  /// `20260703_141522_Motion` → `day004_s01_Motion` (falls back to a plain
  /// sequence name if no timestamp can be parsed — never leaks the raw name).
  String _deidentifyFolderName(String raw, int seq) {
    final s = seq.toString().padLeft(2, '0');
    final m = _folderTsRe.firstMatch(raw);
    var suffix = '';
    if (m != null) {
      // whatever follows the timestamp (e.g. "_Motion") minus leading _/-
      suffix = raw.substring(m.end).replaceFirst(RegExp(r'^[_\-]+'), '');
      final t = DateTime.tryParse(
          '${m.group(1)}-${m.group(2)}-${m.group(3)}T${m.group(4)}:${m.group(5)}:${m.group(6) ?? '00'}');
      if (t != null) {
        return [_dayTag(t), 's$s', if (suffix.isNotEmpty) suffix].join('_');
      }
    }
    return 'session_s$s';
  }

  /// Recursively: drop `notes` keys, convert ISO timestamps to study-day form,
  /// and re-alias the participant code in keys' string values.
  String _scrubJson(String src) {
    dynamic scrub(dynamic v) {
      if (v is Map) {
        return {
          for (final e in v.entries)
            if (e.key != 'notes') e.key: scrub(e.value)
        };
      }
      if (v is List) return [for (final e in v) scrub(e)];
      if (v is String) {
        if (_isoRe.hasMatch(v)) {
          final t = DateTime.tryParse(v);
          if (t != null) {
            final tl = t.toLocal();
            final hh = tl.hour.toString().padLeft(2, '0');
            final mm = tl.minute.toString().padLeft(2, '0');
            final ss = tl.second.toString().padLeft(2, '0');
            return '${_dayTag(t)}T$hh:$mm:$ss';
          }
        }
        if (v == participant.code) return _outId;
        if (v.contains(participant.code)) {
          return v.replaceAll(participant.code, _outId);
        }
      }
      return v;
    }

    try {
      return const JsonEncoder.withIndent('  ').convert(scrub(jsonDecode(src)));
    } catch (_) {
      // Not valid JSON — refuse to pass it through unscrubbed.
      return '{"error": "original file could not be parsed; omitted from export"}';
    }
  }

  String _readme() => '''
De-identified TeleRehab export — $_outId
=========================================

This bundle contains pseudonymous research data only. No names, no calendar
dates. Folder names use study days: dayNNN = days since the participant was
enrolled (day000 = enrolment day), sNN = session sequence number.

Files per session folder
------------------------
session.json      Session manifest (sensor config, class, relative timings)
zed_skeleton.json Body-tracking frames; per-frame time is relative ms
fsr.csv           Plantar pressure samples; relative ms
eeg.csv           EEG samples (uV); relative ms
markers.csv       Protocol block/phase event markers; t_ms is on the
                  recording clock (see run.json markerTimebase)
run.json          Protocol run metadata (sequence, seed, clock offset)
protocol.json     The protocol definition used for the run

Notes fields have been removed. Timestamps inside JSON files use the same
dayNNN convention with time-of-day preserved.
''';
}
