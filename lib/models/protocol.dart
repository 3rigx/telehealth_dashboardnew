import 'dart:math';
import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Protocol model — a research experiment definition built in the Protocol
/// Builder: a set of classes, a block sequence, timing and per-class feedback.
///
/// A protocol is the *design*; a protocol *run* (Phase 3) records one continuous
/// session against it with block/phase markers. Classes map onto the existing
/// capture tokens (Idle/Motion/MotionCognitive) via [ProtocolClass.baseToken]
/// so recording/replay keep working, while carrying their own custom identity.
/// ─────────────────────────────────────────────────────────────────────────

/// Base capture tokens — mirror Unity's `ExerciseClass.ToToken()`.
const kBaseTokens = ['Idle', 'Motion', 'MotionCognitive'];

String baseTokenDisplay(String token) => switch (token) {
      'Idle' => 'Idle (rest)',
      'Motion' => 'Motion',
      'MotionCognitive' => 'Motion + Cognitive',
      _ => token,
    };

/// Palette offered for class theme colours (ARGB ints).
const kClassPalette = <int>[
  0xFF1A6EFA, // blue
  0xFF00C896, // green
  0xFFFF8C00, // orange
  0xFFBB86FC, // purple
  0xFF00D4FF, // cyan
  0xFFFF3B55, // red
  0xFFFFC400, // amber
  0xFF7C4DFF, // indigo
];

enum BlockOrderMode { randomized, counterbalanced, fixed }

extension BlockOrderModeX on BlockOrderMode {
  String get token => switch (this) {
        BlockOrderMode.randomized => 'Randomized',
        BlockOrderMode.counterbalanced => 'Counterbalanced',
        BlockOrderMode.fixed => 'Fixed',
      };

  String get blurb => switch (this) {
        BlockOrderMode.randomized => 'Random order, no class twice in a row',
        BlockOrderMode.counterbalanced => 'Each class once per round, shuffled per round',
        BlockOrderMode.fixed => 'Repeating round-robin order',
      };

  static BlockOrderMode fromToken(String s) => switch (s) {
        'Counterbalanced' => BlockOrderMode.counterbalanced,
        'Fixed' => BlockOrderMode.fixed,
        _ => BlockOrderMode.randomized,
      };
}

/// Participant-visible feedback for a class. Gated globally by
/// [Protocol.globalFeedback] (the master switch).
class ClassFeedback {
  bool movementMirror;
  bool pressureIndicator;
  bool eegFeedback;

  ClassFeedback({
    this.movementMirror = false,
    this.pressureIndicator = false,
    this.eegFeedback = false,
  });

  bool get any => movementMirror || pressureIndicator || eegFeedback;

  Map<String, dynamic> toJson() => {
        'movementMirror': movementMirror,
        'pressureIndicator': pressureIndicator,
        'eegFeedback': eegFeedback,
      };

  factory ClassFeedback.fromJson(Map<String, dynamic> j) => ClassFeedback(
        movementMirror: j['movementMirror'] ?? false,
        pressureIndicator: j['pressureIndicator'] ?? false,
        eegFeedback: j['eegFeedback'] ?? false,
      );

  ClassFeedback clone() => ClassFeedback.fromJson(toJson());
}

/// One experimental condition. Custom identity (name/colour/instruction/
/// exercise/animation/feedback) on top of a base capture token.
class ProtocolClass {
  final String id;
  String name;
  int colorValue;
  String baseToken; // one of kBaseTokens — keeps the capture pipeline compatible
  String instruction;
  String exerciseType; // per-class display name (e.g. "Seated Leg Extensions")
  String exerciseId; // -> authored ExerciseAsset (avatar guide); may be empty
  String animationPath; // per-class reference GIF/MP4 fallback (may be empty)
  bool cognitivePrompt; // shows "count out loud"-style note on participant screen

  // Per-class block timing (seconds). Each class controls its own block length
  // and the reset that follows a block of this class.
  double instructionSec;
  double activeSec;
  double resetSec;

  ClassFeedback feedback;

  ProtocolClass({
    required this.id,
    required this.name,
    required this.colorValue,
    this.baseToken = 'Motion',
    this.instruction = '',
    this.exerciseType = '',
    this.exerciseId = '',
    this.animationPath = '',
    this.cognitivePrompt = false,
    this.instructionSec = 2,
    this.activeSec = 30,
    this.resetSec = 5,
    ClassFeedback? feedback,
  }) : feedback = feedback ?? ClassFeedback();

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'baseToken': baseToken,
        'instruction': instruction,
        'exerciseType': exerciseType,
        'exerciseId': exerciseId,
        'animationPath': animationPath,
        'cognitivePrompt': cognitivePrompt,
        'instructionSec': instructionSec,
        'activeSec': activeSec,
        'resetSec': resetSec,
        'feedback': feedback.toJson(),
      };

  /// [defInstruction]/[defActive]/[defReset] back-fill per-class timing when
  /// loading older protocols that only stored timing at the protocol level.
  factory ProtocolClass.fromJson(
    Map<String, dynamic> j, {
    double defInstruction = 2,
    double defActive = 30,
    double defReset = 5,
  }) =>
      ProtocolClass(
        id: j['id'] ?? genId('c'),
        name: j['name'] ?? 'Class',
        colorValue: j['colorValue'] ?? kClassPalette.first,
        baseToken: j['baseToken'] ?? 'Motion',
        instruction: j['instruction'] ?? '',
        exerciseType: j['exerciseType'] ?? '',
        exerciseId: j['exerciseId'] ?? '',
        animationPath: j['animationPath'] ?? '',
        cognitivePrompt: j['cognitivePrompt'] ?? false,
        instructionSec: (j['instructionSec'] ?? defInstruction).toDouble(),
        activeSec: (j['activeSec'] ?? defActive).toDouble(),
        resetSec: (j['resetSec'] ?? defReset).toDouble(),
        feedback: j['feedback'] is Map<String, dynamic>
            ? ClassFeedback.fromJson(j['feedback'])
            : ClassFeedback(),
      );

  ProtocolClass clone() => ProtocolClass.fromJson(toJson());
}

class Protocol {
  final String id;
  String title;
  List<ProtocolClass> classes;
  int blockCount;
  BlockOrderMode orderMode;
  bool globalFeedback;
  double instructionSec;
  double activeSec;
  double resetSec;
  bool sensorZed;
  bool sensorFsr;
  bool sensorEeg;

  /// Explicit class-id order used only when [orderMode] is fixed and its length
  /// matches the normalised block count; otherwise a round-robin is generated.
  List<String>? fixedOrder;

  int version;
  bool published;
  String createdUtc;
  String updatedUtc;

  Protocol({
    required this.id,
    this.title = 'Untitled Protocol',
    List<ProtocolClass>? classes,
    this.blockCount = 12,
    this.orderMode = BlockOrderMode.randomized,
    this.globalFeedback = true,
    this.instructionSec = 2,
    this.activeSec = 30,
    this.resetSec = 5,
    this.sensorZed = true,
    this.sensorFsr = true,
    this.sensorEeg = true,
    this.fixedOrder,
    this.version = 1,
    this.published = false,
    String? createdUtc,
    String? updatedUtc,
  })  : classes = classes ?? [],
        createdUtc = createdUtc ?? DateTime.now().toUtc().toIso8601String(),
        updatedUtc = updatedUtc ?? DateTime.now().toUtc().toIso8601String();

  /// Blocks must split evenly across classes — round the requested count UP to
  /// the nearest multiple of the class count.
  int get normalizedBlockCount {
    final k = classes.length;
    if (k == 0) return 0;
    if (blockCount < k) return k;
    final rem = blockCount % k;
    return rem == 0 ? blockCount : blockCount + (k - rem);
  }

  bool get blockCountRounded => normalizedBlockCount != blockCount;

  int get blocksPerClass => classes.isEmpty ? 0 : normalizedBlockCount ~/ classes.length;

  /// Estimated run length using each block's per-class timing: every block is
  /// instruction+active, with that class's reset following it (no reset after
  /// the final block). Comfort pauses are researcher-triggered and not counted.
  Duration get estimatedDuration {
    final seq = generateSequence(seed: 1);
    if (seq.isEmpty) return Duration.zero;
    double secs = 0;
    for (var i = 0; i < seq.length; i++) {
      final c = classById(seq[i]);
      if (c == null) continue;
      secs += c.instructionSec + c.activeSec;
      if (i < seq.length - 1) secs += c.resetSec;
    }
    return Duration(seconds: secs.round());
  }

  ProtocolClass? classById(String id) {
    for (final c in classes) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Build a block sequence (list of class ids) honouring [orderMode].
  /// Deterministic given [seed]; the realised order + seed are stored per run.
  List<String> generateSequence({int? seed}) {
    final ids = classes.map((c) => c.id).toList();
    if (ids.isEmpty) return const [];
    final n = normalizedBlockCount;
    final per = n ~/ ids.length;
    final rng = Random(seed ?? DateTime.now().millisecondsSinceEpoch);

    switch (orderMode) {
      case BlockOrderMode.fixed:
        final fo = fixedOrder;
        if (fo != null && fo.length == n && fo.every(ids.contains)) {
          return List.of(fo);
        }
        return [for (var i = 0; i < n; i++) ids[i % ids.length]];

      case BlockOrderMode.counterbalanced:
        final out = <String>[];
        for (var r = 0; r < per; r++) {
          out.addAll(List.of(ids)..shuffle(rng));
        }
        return out;

      case BlockOrderMode.randomized:
        final pool = <String>[for (final id in ids) ...List.filled(per, id)]..shuffle(rng);
        // Repair immediate repeats where possible.
        for (var i = 1; i < pool.length; i++) {
          if (pool[i] == pool[i - 1]) {
            for (var j = i + 1; j < pool.length; j++) {
              if (pool[j] != pool[i - 1] &&
                  (i + 1 >= pool.length || pool[j] != pool[i + 1])) {
                final t = pool[i];
                pool[i] = pool[j];
                pool[j] = t;
                break;
              }
            }
          }
        }
        return pool;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'classes': [for (final c in classes) c.toJson()],
        'blockCount': blockCount,
        'orderMode': orderMode.token,
        'globalFeedback': globalFeedback,
        'instructionSec': instructionSec,
        'activeSec': activeSec,
        'resetSec': resetSec,
        'sensorZed': sensorZed,
        'sensorFsr': sensorFsr,
        'sensorEeg': sensorEeg,
        'fixedOrder': fixedOrder,
        'version': version,
        'published': published,
        'createdUtc': createdUtc,
        'updatedUtc': updatedUtc,
      };

  factory Protocol.fromJson(Map<String, dynamic> j) {
    // Legacy protocol-level timing → used as defaults for new classes and to
    // back-fill per-class timing when loading protocols saved before timing
    // moved onto the class.
    final defInstr = (j['instructionSec'] ?? 2).toDouble();
    final defActive = (j['activeSec'] ?? 30).toDouble();
    final defReset = (j['resetSec'] ?? 5).toDouble();
    return Protocol(
      id: j['id'] ?? genId('p'),
      title: j['title'] ?? 'Untitled Protocol',
      classes: [
        for (final c in (j['classes'] as List? ?? const []))
          if (c is Map<String, dynamic>)
            ProtocolClass.fromJson(c,
                defInstruction: defInstr, defActive: defActive, defReset: defReset),
      ],
      blockCount: j['blockCount'] ?? 12,
      orderMode: BlockOrderModeX.fromToken(j['orderMode'] ?? 'Randomized'),
      globalFeedback: j['globalFeedback'] ?? true,
      instructionSec: defInstr,
      activeSec: defActive,
      resetSec: defReset,
      sensorZed: j['sensorZed'] ?? true,
      sensorFsr: j['sensorFsr'] ?? true,
      sensorEeg: j['sensorEeg'] ?? true,
      fixedOrder: (j['fixedOrder'] as List?)?.map((e) => e.toString()).toList(),
      version: j['version'] ?? 1,
      published: j['published'] ?? false,
      createdUtc: j['createdUtc'],
      updatedUtc: j['updatedUtc'],
    );
  }

  /// Deep copy (used to edit a working draft without aliasing the stored one).
  Protocol clone() => Protocol.fromJson(toJson());

  /// A blank protocol with one starter class.
  factory Protocol.blank() => Protocol(
        id: genId('p'),
        title: 'Untitled Protocol',
        classes: [
          ProtocolClass(
            id: genId('c'),
            name: 'Class 1',
            colorValue: kClassPalette.first,
            baseToken: 'Motion',
            instruction: '',
          ),
        ],
        blockCount: 4,
      );

  /// The familiar REST / MOVE / MOVE+COUNT seated-exercise template.
  factory Protocol.template() => Protocol(
        id: genId('p'),
        title: 'Generic Seated Exercise Study',
        blockCount: 12,
        orderMode: BlockOrderMode.randomized,
        classes: [
          ProtocolClass(
            id: genId('c'),
            name: 'REST',
            colorValue: 0xFF1A6EFA,
            baseToken: 'Idle',
            instruction: 'Please relax and remain still in your seated position.',
            exerciseType: 'Rest',
            feedback: ClassFeedback(),
          ),
          ProtocolClass(
            id: genId('c'),
            name: 'MOVE',
            colorValue: 0xFF00C896,
            baseToken: 'Motion',
            instruction: 'Do seated leg extensions continuously.',
            exerciseType: 'Seated Leg Extensions',
            feedback: ClassFeedback(
                movementMirror: true, pressureIndicator: true),
          ),
          ProtocolClass(
            id: genId('c'),
            name: 'MOVE + COUNT',
            colorValue: 0xFFFF8C00,
            baseToken: 'MotionCognitive',
            instruction: 'Do seated leg extensions and count out loud.',
            exerciseType: 'Seated Leg Extensions',
            cognitivePrompt: true,
            feedback: ClassFeedback(
                movementMirror: true, pressureIndicator: true),
          ),
        ],
      );
}

/// Compact, dependency-free unique id (avoids adding a uuid package).
String genId(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${Random().nextInt(0x46655).toRadixString(36)}';
