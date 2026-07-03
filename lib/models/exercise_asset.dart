import 'protocol.dart' show genId;

enum ExerciseSource { recorded, uploaded }

extension ExerciseSourceToken on ExerciseSource {
  String get token => this == ExerciseSource.recorded ? 'recorded' : 'uploaded';
  static ExerciseSource fromToken(String? t) =>
      t == 'uploaded' ? ExerciseSource.uploaded : ExerciseSource.recorded;
}

/// An authored exercise: a reusable reference movement shown to the participant
/// as the block guide. Either a RECORDED skeleton-avatar clip (a ZED capture
/// played back on the bone avatar) or an UPLOADED media file (gif/video).
///
/// Stored as `<exercisesRoot>/<id>/exercise.json` plus its clip file
/// (`skeleton.json` for recorded clips — same shape as Unity's
/// zed_skeleton.json — or the uploaded media file).
class ExerciseAsset {
  final String id;
  String name;
  String notes;
  final ExerciseSource source;

  /// Filename inside the exercise's folder: `skeleton.json` for recorded clips,
  /// or the uploaded media file name for uploaded exercises.
  final String clipFile;

  final int bodyFormat; // ZED body format of the recorded clip
  final int frameCount;
  final int durationMs;
  final String createdUtc;
  String updatedUtc;

  ExerciseAsset({
    String? id,
    required this.name,
    this.notes = '',
    this.source = ExerciseSource.recorded,
    this.clipFile = 'skeleton.json',
    this.bodyFormat = 1,
    this.frameCount = 0,
    this.durationMs = 0,
    String? createdUtc,
    String? updatedUtc,
  })  : id = id ?? genId('e'),
        createdUtc = createdUtc ?? DateTime.now().toUtc().toIso8601String(),
        updatedUtc = updatedUtc ?? DateTime.now().toUtc().toIso8601String();

  bool get isRecorded => source == ExerciseSource.recorded;
  DateTime? get createdAt => DateTime.tryParse(createdUtc)?.toLocal();
  Duration get duration => Duration(milliseconds: durationMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'source': source.token,
        'clipFile': clipFile,
        'bodyFormat': bodyFormat,
        'frameCount': frameCount,
        'durationMs': durationMs,
        'createdUtc': createdUtc,
        'updatedUtc': updatedUtc,
      };

  factory ExerciseAsset.fromJson(Map<String, dynamic> j) => ExerciseAsset(
        id: j['id'],
        name: j['name'] ?? 'Untitled exercise',
        notes: j['notes'] ?? '',
        source: ExerciseSourceToken.fromToken(j['source']),
        clipFile: j['clipFile'] ?? 'skeleton.json',
        bodyFormat: j['bodyFormat'] ?? 1,
        frameCount: j['frameCount'] ?? 0,
        durationMs: j['durationMs'] ?? 0,
        createdUtc: j['createdUtc'],
        updatedUtc: j['updatedUtc'],
      );
}
