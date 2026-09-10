import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../models/exercise_asset.dart';
import '../models/session_models.dart' show SkeletonFrame, skeletonFromUnityJson;
import '../models/skeleton_3d.dart';
import 'session_repository.dart' show cumulativeTimeline;

/// Stores authored exercises as one folder per exercise under [root]:
///   `<exercisesRoot>/<id>/exercise.json` + `skeleton.json` (recorded) or the
///   uploaded media file. Recorded clips reuse Unity's `zed_skeleton.json` shape
///   so they parse with the same loader as recorded sessions.
class ExerciseRepository extends ChangeNotifier {
  String _root = '';
  List<ExerciseAsset> exercises = [];

  String get root => _root;

  void setRoot(String root) {
    if (root == _root) return;
    _root = root;
    refresh();
  }

  String _dirFor(String id) => '$_root${Platform.pathSeparator}$id';
  String _metaFor(String id) =>
      '${_dirFor(id)}${Platform.pathSeparator}exercise.json';

  /// Absolute path to an exercise's clip / media file.
  String clipPath(ExerciseAsset e) =>
      '${_dirFor(e.id)}${Platform.pathSeparator}${e.clipFile}';

  Future<void> refresh() async {
    final loaded = <ExerciseAsset>[];
    try {
      final dir = Directory(_root);
      if (await dir.exists()) {
        for (final d in dir.listSync().whereType<Directory>()) {
          final meta = File('${d.path}${Platform.pathSeparator}exercise.json');
          if (!await meta.exists()) continue;
          try {
            loaded.add(ExerciseAsset.fromJson(
                jsonDecode(await meta.readAsString()) as Map<String, dynamic>));
          } catch (e) {
            debugPrint('Skipping unreadable exercise ${d.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Exercise refresh failed: $e');
    }
    loaded.sort((a, b) => b.updatedUtc.compareTo(a.updatedUtc)); // newest first
    exercises = loaded;
    notifyListeners();
  }

  ExerciseAsset? byId(String id) {
    for (final e in exercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> save(ExerciseAsset e) async {
    e.updatedUtc = DateTime.now().toUtc().toIso8601String();
    final dir = Directory(_dirFor(e.id));
    if (!await dir.exists()) await dir.create(recursive: true);
    await File(_metaFor(e.id))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(e.toJson()));
    final i = exercises.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      exercises[i] = e;
    } else {
      exercises.insert(0, e);
    }
    exercises.sort((a, b) => b.updatedUtc.compareTo(a.updatedUtc));
    notifyListeners();
  }

  /// Create a recorded exercise by importing a Unity `zed_skeleton.json` (from a
  /// live authoring capture, or an existing recorded session). Copies the frames
  /// into the exercise folder and records their count/duration/body format.
  Future<ExerciseAsset> importFromSkeletonJson(String name, String srcPath) async {
    final base = ExerciseAsset(name: name, source: ExerciseSource.recorded);
    final dir = Directory(_dirFor(base.id));
    if (!await dir.exists()) await dir.create(recursive: true);
    final bytes = await File(srcPath).readAsBytes();
    await File('${dir.path}${Platform.pathSeparator}${base.clipFile}')
        .writeAsBytes(bytes);

    var bodyFormat = 1, frameCount = 0, durationMs = 0;
    try {
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      bodyFormat = j['bodyFormat'] ?? 1;
      final rawT = <int>[];
      for (final fr in (j['frames'] as List? ?? const [])) {
        if (fr is Map<String, dynamic> && fr['skeleton'] is Map<String, dynamic>) {
          rawT.add(fr['tMs'] ?? 0);
        }
      }
      frameCount = rawT.length;
      final times = cumulativeTimeline(rawT);
      durationMs = times.isEmpty ? 0 : times.last;
    } catch (e) {
      debugPrint('importFromSkeletonJson parse failed: $e');
    }

    final finished = ExerciseAsset(
      id: base.id,
      name: name,
      source: ExerciseSource.recorded,
      clipFile: base.clipFile,
      bodyFormat: bodyFormat,
      frameCount: frameCount,
      durationMs: durationMs,
      createdUtc: base.createdUtc,
    );
    await save(finished);
    return finished;
  }

  /// Create an "uploaded media" exercise by copying a gif/webp/video file into
  /// the exercise folder. It is rendered directly (looping image or video),
  /// not as an avatar, wherever a guide is shown.
  Future<ExerciseAsset> importMedia(String name, String srcPath) async {
    final ext = srcPath.contains('.') ? srcPath.split('.').last.toLowerCase() : 'bin';
    final clip = 'media.$ext';
    final asset =
        ExerciseAsset(name: name, source: ExerciseSource.uploaded, clipFile: clip);
    final dir = Directory(_dirFor(asset.id));
    if (!await dir.exists()) await dir.create(recursive: true);
    await File(srcPath).copy('${dir.path}${Platform.pathSeparator}$clip');
    await save(asset);
    return asset;
  }

  /// Load a recorded exercise's skeleton frames for avatar playback (rebuilding
  /// the timeline exactly as the replay loader does).
  Future<List<SkeletonFrame>> loadFrames(ExerciseAsset e) async {
    if (!e.isRecorded) return const [];
    try {
      final f = File(clipPath(e));
      if (!await f.exists()) return const [];
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final bodyFormat = j['bodyFormat'] ?? e.bodyFormat;
      final rawT = <int>[];
      final skels = <Skeleton3D>[];
      for (final fr in (j['frames'] as List? ?? const [])) {
        if (fr is! Map<String, dynamic>) continue;
        final sk = fr['skeleton'];
        if (sk is! Map<String, dynamic>) continue;
        final skeleton = skeletonFromUnityJson(sk, bodyFormat);
        if (skeleton != null) {
          rawT.add(fr['tMs'] ?? 0);
          skels.add(skeleton);
        }
      }
      final times = cumulativeTimeline(rawT);
      return [
        for (var i = 0; i < skels.length; i++)
          SkeletonFrame(tMs: times[i], skeleton: skels[i]),
      ];
    } catch (e2) {
      debugPrint('Exercise loadFrames failed: $e2');
      return const [];
    }
  }

  Future<void> delete(String id) async {
    try {
      final dir = Directory(_dirFor(id));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('Exercise delete failed: $e');
    }
    exercises.removeWhere((x) => x.id == id);
    notifyListeners();
  }
}
