import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/participant.dart';

/// Registry of enrolled participants — pseudonymous codes + consent status
/// only (see [Participant] for the privacy rationale). Persisted as a single
/// `participants.json` under [root].
///
/// Enforcement contract: sessions and protocol runs must use a code from this
/// registry (picked, never typed), so no free-text identity can ever reach a
/// folder name or data file.
class ParticipantRepository extends ChangeNotifier {
  String root = '';
  List<Participant> participants = [];
  String lastError = '';

  static const _codePrefix = 'P';

  File get _file => File('$root${Platform.pathSeparator}participants.json');

  Future<void> setRoot(String r) async {
    root = r;
    await refresh();
  }

  Future<void> refresh() async {
    lastError = '';
    try {
      if (root.isEmpty || !_file.existsSync()) {
        participants = [];
      } else {
        final j = jsonDecode(await _file.readAsString());
        participants = [
          for (final e in (j['participants'] as List? ?? []))
            Participant.fromJson(e as Map<String, dynamic>)
        ];
      }
    } catch (e) {
      lastError = 'Could not read participants.json: $e';
      participants = [];
    }
    notifyListeners();
  }

  Participant? byCode(String code) {
    for (final p in participants) {
      if (p.code == code) return p;
    }
    return null;
  }

  /// Participants selectable for a new session (consented + not withdrawn).
  List<Participant> get selectable =>
      participants.where((p) => p.status == ParticipantStatus.active).toList();

  /// Next free code: P-001, P-002, … (never reuses a code, even after
  /// withdrawal — codes must stay unique for the life of the study).
  String nextCode() {
    var maxN = 0;
    final re = RegExp('^$_codePrefix-(\\d+)\$');
    for (final p in participants) {
      final m = re.firstMatch(p.code);
      if (m != null) maxN = max(maxN, int.parse(m.group(1)!));
    }
    return '$_codePrefix-${(maxN + 1).toString().padLeft(3, '0')}';
  }

  static int max(int a, int b) => a > b ? a : b;

  /// Enrols a new participant. Consent must already be obtained (the UI gates
  /// on the consent checklist before calling this).
  Future<Participant> enrol({
    required String consentVersion,
    ParticipantGender gender = ParticipantGender.unspecified,
    String notes = '',
  }) async {
    final now = DateTime.now().toUtc();
    final p = Participant(
      code: nextCode(),
      enrolledUtc: now,
      consentVersion: consentVersion,
      consentUtc: now,
      gender: gender,
      notes: notes,
    );
    participants.add(p);
    await _persist();
    return p;
  }

  Future<void> setStatus(String code, ParticipantStatus status) async {
    final p = byCode(code);
    if (p == null) return;
    p.status = status;
    p.statusChangedUtc = DateTime.now().toUtc();
    await _persist();
  }

  Future<void> updateNotes(String code, String notes) async {
    final p = byCode(code);
    if (p == null) return;
    p.notes = notes;
    await _persist();
  }

  /// Removes a participant from the registry. Their recorded data folders are
  /// NOT touched here — data deletion is a separate, explicit act (see the
  /// Participants screen's "Delete recorded data" flow).
  Future<void> remove(String code) async {
    participants.removeWhere((p) => p.code == code);
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final dir = Directory(root);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await _file.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'schema': 'telerehab.participants.v1',
        'note': 'Pseudonymous registry. The code-to-identity link is kept '
            'outside this software by design.',
        'participants': [for (final p in participants) p.toJson()],
      }));
      lastError = '';
    } catch (e) {
      lastError = 'Could not save participants.json: $e';
    }
    notifyListeners();
  }
}
