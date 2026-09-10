import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'exercise_repository.dart';
import 'unity_connection_service.dart';
import 'unity_launch_service.dart';

enum RecordStage {
  idle,
  connecting,
  preparing,
  ready,
  recording,
  saving,
  done,
  error
}

/// Records a clinician's exercise demonstration with the ZED and saves it as an
/// avatar exercise. Reuses the normal capture pipeline (configure → start_session
/// → warm-up → start_recording → stop_recording → session_saved), then imports
/// the resulting `zed_skeleton.json` into the [ExerciseRepository].
///
/// ZED-only (FSR/EEG off), so it never touches the insole port.
class ExerciseRecordController extends ChangeNotifier {
  final UnityConnectionService conn;
  final AppSettings settings;
  final ExerciseRepository exercises;
  final String name;

  /// When provided, [prepare] launches the Unity player itself if it isn't
  /// already running.
  final UnityLaunchService? launcher;

  RecordStage stage = RecordStage.idle;
  String message = '';
  String? savedExerciseId;

  DateTime? _saveBaseline;
  bool _connListening = false;
  bool _handled = false;
  Timer? _prepTimer;
  final Stopwatch _watch = Stopwatch();

  ExerciseRecordController({
    required this.conn,
    required this.settings,
    required this.exercises,
    required this.name,
    this.launcher,
  });

  int get elapsedMs => _watch.elapsed.inMilliseconds;

  void _set(RecordStage s, [String msg = '']) {
    stage = s;
    message = msg;
    notifyListeners();
  }

  Future<void> prepare() async {
    // Attach to a running Unity, or launch the configured/bundled player —
    // recording must work from a cold start, like the home-screen flow.
    final err = await ensureUnityConnected(
      conn: conn,
      settings: settings,
      launcher: launcher,
      onStatus: (m) => _set(RecordStage.connecting, m),
    );
    if (err != null) {
      _set(RecordStage.error, err);
      return;
    }

    // Real data, ZED only.
    conn.setMocks(motion: false, fsr: false, eeg: false);
    _set(RecordStage.preparing, 'Configuring the camera…');
    conn.configureSession({
      'patientId': '_exercises', // authoring recordings live under their own id
      'exerciseClass': 'Motion',
      'mode': 'Exercise',
      'zed': true,
      'fsr': false,
      'eeg': false,
    });
    await Future.delayed(const Duration(milliseconds: 400));
    conn.startSession();
    if (!_connListening) {
      conn.addListener(_onConn);
      _connListening = true;
    }

    if (conn.receivingLive) {
      _toReady();
    } else {
      _set(RecordStage.preparing, 'Warming up the camera… (up to ~20 s)');
      _prepTimer =
          Timer(const Duration(seconds: 25), () => _toReady(timedOut: true));
    }
  }

  void _toReady({bool timedOut = false}) {
    _prepTimer?.cancel();
    _prepTimer = null;
    if (stage == RecordStage.ready || stage == RecordStage.recording) return;
    _set(
        RecordStage.ready,
        timedOut
            ? 'Camera didn’t confirm warm-up — you can still record, but check the ZED if the preview stays empty.'
            : 'Stand in view, then Record and perform the movement a few times.');
  }

  void begin() {
    if (stage != RecordStage.ready) return;
    conn.startRecording();
    _watch
      ..reset()
      ..start();
    _set(RecordStage.recording);
  }

  void stop() {
    if (stage != RecordStage.recording) return;
    _watch.stop();
    _saveBaseline = DateTime.now();
    conn.stopRecording();
    _set(RecordStage.saving, 'Saving…');
  }

  void _onConn() {
    if (stage == RecordStage.preparing && conn.receivingLive) {
      _toReady();
      return;
    }
    if (stage != RecordStage.saving) return;
    final s = conn.lastSaved;
    if (s == null) return;
    if (_saveBaseline != null && s.receivedAt.isBefore(_saveBaseline!)) return;
    _import(s.folder);
  }

  Future<void> _import(String folder) async {
    if (_handled) return; // handle the save once
    _handled = true;
    _set(RecordStage.saving, 'Importing the avatar…');
    try {
      final sep = Platform.pathSeparator;
      final asset = await exercises.importFromSkeletonJson(
          name, '$folder${sep}zed_skeleton.json');
      savedExerciseId = asset.id;
      if (asset.frameCount == 0) {
        _set(RecordStage.error,
            'No motion was captured — check that the ZED tracked a body, and try again.');
      } else {
        _set(RecordStage.done, 'Saved “$name” · ${asset.frameCount} frames');
      }
    } catch (e) {
      _set(RecordStage.error, 'Recorded, but importing the avatar failed: $e');
    }
  }

  @override
  void dispose() {
    _prepTimer?.cancel();
    // Leaving mid-flow ends the Unity capture so it isn't left recording.
    if (stage == RecordStage.preparing ||
        stage == RecordStage.ready ||
        stage == RecordStage.recording) {
      conn.stopRecording();
    }
    if (_connListening) conn.removeListener(_onConn);
    super.dispose();
  }
}
