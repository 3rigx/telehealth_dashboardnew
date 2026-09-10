/// A study participant, identified ONLY by a pseudonymous code (P-001, …).
///
/// PRIVACY BY DESIGN: this model deliberately has no name, contact or
/// date-of-birth fields. The link between a code and a real identity is kept
/// OUTSIDE this software (paper enrolment log / the PI's separate encrypted
/// file), so the dashboard — and anything exported from it — cannot leak
/// identities it never held.
enum ParticipantStatus { active, withdrawn, completed }

extension ParticipantStatusInfo on ParticipantStatus {
  String get token => switch (this) {
        ParticipantStatus.active => 'active',
        ParticipantStatus.withdrawn => 'withdrawn',
        ParticipantStatus.completed => 'completed',
      };

  String get label => switch (this) {
        ParticipantStatus.active => 'Active',
        ParticipantStatus.withdrawn => 'Withdrawn',
        ParticipantStatus.completed => 'Completed',
      };

  static ParticipantStatus fromToken(String? t) => switch (t) {
        'withdrawn' => ParticipantStatus.withdrawn,
        'completed' => ParticipantStatus.completed,
        _ => ParticipantStatus.active,
      };
}

/// Structured demographic — deliberately an enum, not free text, so nothing
/// identifying can be typed into it. Not a HIPAA identifier; kept in
/// de-identified exports (unlike `notes`, which is stripped).
enum ParticipantGender { unspecified, female, male, nonBinary, notDisclosed }

extension ParticipantGenderInfo on ParticipantGender {
  String get token => switch (this) {
        ParticipantGender.unspecified => 'unspecified',
        ParticipantGender.female => 'female',
        ParticipantGender.male => 'male',
        ParticipantGender.nonBinary => 'non_binary',
        ParticipantGender.notDisclosed => 'not_disclosed',
      };

  String get label => switch (this) {
        ParticipantGender.unspecified => '—',
        ParticipantGender.female => 'Female',
        ParticipantGender.male => 'Male',
        ParticipantGender.nonBinary => 'Non-binary',
        ParticipantGender.notDisclosed => 'Prefer not to say',
      };

  static ParticipantGender fromToken(String? t) => switch (t) {
        'female' => ParticipantGender.female,
        'male' => ParticipantGender.male,
        'non_binary' => ParticipantGender.nonBinary,
        'not_disclosed' => ParticipantGender.notDisclosed,
        _ => ParticipantGender.unspecified,
      };
}

class Participant {
  final String code; // e.g. "P-001" — the ONLY identifier, used everywhere
  final DateTime enrolledUtc;
  final String consentVersion; // e.g. "v1.0" — which consent form was signed
  final DateTime consentUtc;
  ParticipantStatus status;
  DateTime? statusChangedUtc;
  ParticipantGender gender;

  /// Free clinical context (e.g. "left-side weakness"). MUST NOT contain
  /// identifying information; stripped from de-identified exports regardless.
  String notes;

  Participant({
    required this.code,
    required this.enrolledUtc,
    required this.consentVersion,
    required this.consentUtc,
    this.status = ParticipantStatus.active,
    this.statusChangedUtc,
    this.gender = ParticipantGender.unspecified,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'enrolledUtc': enrolledUtc.toIso8601String(),
        'consentVersion': consentVersion,
        'consentUtc': consentUtc.toIso8601String(),
        'status': status.token,
        if (statusChangedUtc != null)
          'statusChangedUtc': statusChangedUtc!.toIso8601String(),
        'gender': gender.token,
        'notes': notes,
      };

  factory Participant.fromJson(Map<String, dynamic> j) => Participant(
        code: j['code'] ?? '',
        enrolledUtc:
            DateTime.tryParse(j['enrolledUtc'] ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        consentVersion: j['consentVersion'] ?? '',
        consentUtc:
            DateTime.tryParse(j['consentUtc'] ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        status: ParticipantStatusInfo.fromToken(j['status']),
        statusChangedUtc: DateTime.tryParse(j['statusChangedUtc'] ?? '')?.toUtc(),
        gender: ParticipantGenderInfo.fromToken(j['gender']),
        notes: j['notes'] ?? '',
      );
}
