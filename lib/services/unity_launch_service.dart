import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UnityProcessStatus { notRunning, launching, running, error }

class UnityLaunchService extends ChangeNotifier {
  static const _prefKeyExePath = 'unity_exe_path';

  Process? _process;
  UnityProcessStatus _status = UnityProcessStatus.notRunning;
  String _exePath = '';
  String _lastError = '';

  UnityProcessStatus get status => _status;
  String get exePath => _exePath;
  String get lastError => _lastError;
  bool get isRunning => _status == UnityProcessStatus.running;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _exePath = prefs.getString(_prefKeyExePath) ?? '';
    notifyListeners();
  }

  Future<void> setExePath(String path) async {
    _exePath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyExePath, path);
    notifyListeners();
  }

  /// Launch the Unity executable (or skip if already running).
  Future<bool> launch() async {
    if (_status == UnityProcessStatus.running) return true;
    if (_exePath.isEmpty) {
      _lastError = 'Unity executable path not set.';
      notifyListeners();
      return false;
    }
    if (!File(_exePath).existsSync()) {
      _lastError = 'File not found: $_exePath';
      _status = UnityProcessStatus.error;
      notifyListeners();
      return false;
    }

    _status = UnityProcessStatus.launching;
    notifyListeners();

    try {
      _process = await Process.start(
        _exePath,
        [],
        mode: ProcessStartMode.detachedWithStdio,
      );
      _status = UnityProcessStatus.running;
      _lastError = '';

      // Watch for unexpected exit
      _process!.exitCode.then((_) {
        _process = null;
        _status = UnityProcessStatus.notRunning;
        notifyListeners();
      });

      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      _status = UnityProcessStatus.error;
      notifyListeners();
      return false;
    }
  }

  void stop() {
    _process?.kill();
    _process = null;
    _status = UnityProcessStatus.notRunning;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
