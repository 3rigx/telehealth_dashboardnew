import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';
import 'unity_connection_service.dart';

enum UnityProcessStatus { notRunning, launching, running, error }

/// Makes sure Unity is running AND the WebSocket bridge is connected:
/// attach to an already-running instance first (never spawn a duplicate),
/// launch the configured/bundled player if needed, then poll while the
/// engine boots. Returns null on success, otherwise an operator-facing
/// error message. Used by every flow that drives Unity (home session setup,
/// protocol Run live, exercise recording).
Future<String?> ensureUnityConnected({
  required UnityConnectionService conn,
  required AppSettings settings,
  UnityLaunchService? launcher,
  void Function(String message)? onStatus,
}) async {
  if (conn.isConnected) return null;
  onStatus?.call('Connecting to Unity…');
  await conn.connect(settings.wsUri);
  if (conn.isConnected) return null;

  if (launcher != null && !launcher.isRunning) {
    if (launcher.exePath.isEmpty) await launcher.init(); // pick up auto-detect
    onStatus?.call('Launching Unity…');
    final ok = await launcher.launch();
    if (!ok) {
      return launcher.lastError.isEmpty
          ? 'Could not launch Unity — set the executable path in Settings → Unity Engine.'
          : 'Could not launch Unity: ${launcher.lastError}';
    }
  }

  onStatus?.call('Waiting for Unity to start… (up to ~25 s)');
  for (var i = 0; i < 12 && !conn.isConnected; i++) {
    await Future.delayed(const Duration(seconds: 2));
    await conn.connect(settings.wsUri);
  }
  if (conn.isConnected) return null;
  return 'Unity did not answer on ${settings.wsUri}. '
      'Start the Smart Game app manually, then try again.';
}

class UnityLaunchService extends ChangeNotifier {
  static const _prefKeyExePath = 'unity_exe_path';

  Process? _process;
  UnityProcessStatus _status = UnityProcessStatus.notRunning;
  String _exePath = '';
  String _lastError = '';
  Timer? _liveTimer;

  UnityProcessStatus get status => _status;
  String get exePath => _exePath;
  String get lastError => _lastError;
  bool get isRunning => _status == UnityProcessStatus.running;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _exePath = prefs.getString(_prefKeyExePath) ?? '';
    // Installer bundle: when no path is set (or it's stale), look for a Unity
    // player installed alongside the dashboard — the setup wizard lays out
    //   <install dir>\dashboard\telehealth_dashboard.exe
    //   <install dir>\unity\<player>.exe
    // so a bundled install needs zero configuration.
    if (_exePath.isEmpty || !File(_exePath).existsSync()) {
      final detected = _detectBundledUnity();
      if (detected != null) {
        _exePath = detected;
        await prefs.setString(_prefKeyExePath, detected);
      }
    }
    notifyListeners();
  }

  String? _detectBundledUnity() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final unityDir =
          Directory('${exeDir.parent.path}${Platform.pathSeparator}unity');
      if (!unityDir.existsSync()) return null;
      for (final f in unityDir.listSync().whereType<File>()) {
        final name = f.path.split(Platform.pathSeparator).last.toLowerCase();
        if (name.endsWith('.exe') && !name.contains('crashhandler')) {
          return f.path;
        }
      }
    } catch (_) {}
    return null;
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
      // Fully detached: no stdio pipes (an undrained pipe could block the
      // player mid-session) and Unity survives if the dashboard closes.
      // NOTE: a detached Process only exposes `pid` — touching `exitCode`
      // throws "Bad state: Process is detached", which is exactly the bug
      // this replaced. Liveness is watched by polling the pid instead.
      _process = await Process.start(
        _exePath,
        [],
        mode: ProcessStartMode.detached,
      );
      _status = UnityProcessStatus.running;
      _lastError = '';
      _watchLiveness();
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      _status = UnityProcessStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Detached processes give no exit event — poll the pid so the status line
  /// (and relaunch logic) recover when Unity is closed or crashes.
  void _watchLiveness() {
    _liveTimer?.cancel();
    final pid = _process?.pid;
    if (pid == null) return;
    _liveTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      try {
        final r =
            await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
        if (!(r.stdout as String).contains('$pid')) {
          t.cancel();
          _process = null;
          _status = UnityProcessStatus.notRunning;
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  void stop() {
    _liveTimer?.cancel();
    final p = _process;
    if (p != null) {
      try {
        Process.killPid(p.pid); // pid-based kill works for detached processes
      } catch (_) {}
    }
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
