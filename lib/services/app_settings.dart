import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FSR connection types — values mirror Unity's `FSRConntype` PlayerPrefs strings.
const kFsrConnTypes = ['Mock', 'USB', 'WebSocket', 'TCP'];

/// Exercise classes — tokens mirror Unity's `ExerciseClass.ToToken()`.
const kExerciseClasses = ['Idle', 'Motion', 'MotionCognitive'];

String exerciseClassDisplay(String token) => switch (token) {
      'Idle' => 'Idle',
      'Motion' => 'Motion',
      'MotionCognitive' => 'Motion + Cognitive',
      _ => token,
    };

/// All dashboard-side configuration, persisted with shared_preferences.
/// Sensor keys mirror the Unity settings screen so the same values can be
/// pushed to Unity over the WebSocket as a `configure_session` command.
class AppSettings extends ChangeNotifier {
  static const _kFsrConnType = 'fsr_conn_type';
  static const _kFsrUsbPort = 'fsr_usb_port';
  static const _kFsrUri = 'fsr_uri';
  static const _kFsrApiKey = 'fsr_api_key';
  static const _kZedEnabled = 'zed_enabled';
  static const _kFsrEnabled = 'fsr_enabled';
  static const _kEegEnabled = 'eeg_enabled';
  static const _kMockMotion = 'mock_motion';
  static const _kMockFsr = 'mock_fsr';
  static const _kMockEeg = 'mock_eeg';
  static const _kSessionsRoot = 'sessions_root';
  static const _kProtocolsRoot = 'protocols_root';
  static const _kExercisesRoot = 'exercises_root';
  static const _kWsUri = 'ws_uri';
  static const _kLastPatientId = 'last_patient_id';
  static const _kDarkMode = 'dark_mode';

  SharedPreferences? _prefs;

  String fsrConnType = 'Mock';
  String fsrUsbPort = '';
  String fsrUri = '';
  String fsrApiKey = '';

  bool zedEnabled = true;
  bool fsrEnabled = true;
  bool eegEnabled = false;

  // Dashboard-side mock data, per sensor. Lets you test the live view and
  // replay without hardware — mocked sensors animate locally while any
  // non-mocked sensor still shows real Unity data.
  bool mockMotion = false;
  bool mockFsr = false;
  bool mockEeg = false;

  String sessionsRoot = '';
  String protocolsRoot = '';
  String exercisesRoot = '';
  String wsUri = 'ws://localhost:8765';
  String lastPatientId = '';
  bool darkMode = false;

  List<String> availablePorts = [];

  bool get anyMock => mockMotion || mockFsr || mockEeg;
  bool get allMock => mockMotion && mockFsr && mockEeg;

  /// Default location where the Unity build writes sessions:
  /// %USERPROFILE%\AppData\LocalLow\<company>\<product>\Sessions
  static String defaultSessionsRoot() {
    final home = Platform.environment['USERPROFILE'] ?? '';
    return '$home\\AppData\\LocalLow\\DefaultCompany\\Smart Game\\Sessions';
  }

  /// Protocol definitions live alongside sessions, in a sibling `Protocols`
  /// folder by default.
  static String defaultProtocolsRoot() {
    final home = Platform.environment['USERPROFILE'] ?? '';
    return '$home\\AppData\\LocalLow\\DefaultCompany\\Smart Game\\Protocols';
  }

  /// Authored exercises (recorded skeleton-avatar clips + uploaded media) live
  /// in a sibling `Exercises` folder by default.
  static String defaultExercisesRoot() {
    final home = Platform.environment['USERPROFILE'] ?? '';
    return '$home\\AppData\\LocalLow\\DefaultCompany\\Smart Game\\Exercises';
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    fsrConnType = p.getString(_kFsrConnType) ?? 'Mock';
    fsrUsbPort = p.getString(_kFsrUsbPort) ?? '';
    fsrUri = p.getString(_kFsrUri) ?? '';
    fsrApiKey = p.getString(_kFsrApiKey) ?? '';
    zedEnabled = p.getBool(_kZedEnabled) ?? true;
    fsrEnabled = p.getBool(_kFsrEnabled) ?? true;
    eegEnabled = p.getBool(_kEegEnabled) ?? false;
    mockMotion = p.getBool(_kMockMotion) ?? false;
    mockFsr = p.getBool(_kMockFsr) ?? false;
    mockEeg = p.getBool(_kMockEeg) ?? false;
    sessionsRoot = p.getString(_kSessionsRoot) ?? defaultSessionsRoot();
    protocolsRoot = p.getString(_kProtocolsRoot) ?? defaultProtocolsRoot();
    exercisesRoot = p.getString(_kExercisesRoot) ?? defaultExercisesRoot();
    wsUri = p.getString(_kWsUri) ?? 'ws://localhost:8765';
    lastPatientId = p.getString(_kLastPatientId) ?? '';
    darkMode = p.getBool(_kDarkMode) ?? false;
    notifyListeners();
    refreshPorts();
  }

  /// Enumerate serial ports the same way Unity does
  /// (System.IO.Ports.SerialPort.GetPortNames), via PowerShell.
  Future<void> refreshPorts() async {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '[System.IO.Ports.SerialPort]::GetPortNames() -join ","',
      ]);
      final out = (r.stdout as String).trim();
      availablePorts = out.isEmpty
          ? []
          : (out.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
            ..sort());
    } catch (_) {
      availablePorts = [];
    }
    notifyListeners();
  }

  void _save(void Function(SharedPreferences p) write) {
    final p = _prefs;
    if (p != null) write(p);
    notifyListeners();
  }

  void setFsrConnType(String v) {
    fsrConnType = v;
    _save((p) => p.setString(_kFsrConnType, v));
  }

  void setFsrUsbPort(String v) {
    fsrUsbPort = v;
    _save((p) => p.setString(_kFsrUsbPort, v));
  }

  void setFsrUri(String v) {
    fsrUri = v.trim();
    _save((p) => p.setString(_kFsrUri, fsrUri));
  }

  void setFsrApiKey(String v) {
    fsrApiKey = v.trim();
    _save((p) => p.setString(_kFsrApiKey, fsrApiKey));
  }

  void setZedEnabled(bool v) {
    zedEnabled = v;
    _save((p) => p.setBool(_kZedEnabled, v));
  }

  void setFsrEnabled(bool v) {
    fsrEnabled = v;
    _save((p) => p.setBool(_kFsrEnabled, v));
  }

  void setEegEnabled(bool v) {
    eegEnabled = v;
    _save((p) => p.setBool(_kEegEnabled, v));
  }

  void setMockMotion(bool v) {
    mockMotion = v;
    _save((p) => p.setBool(_kMockMotion, v));
  }

  void setMockFsr(bool v) {
    mockFsr = v;
    _save((p) => p.setBool(_kMockFsr, v));
  }

  void setMockEeg(bool v) {
    mockEeg = v;
    _save((p) => p.setBool(_kMockEeg, v));
  }

  void setAllMock(bool v) {
    mockMotion = v;
    mockFsr = v;
    mockEeg = v;
    _save((p) {
      p.setBool(_kMockMotion, v);
      p.setBool(_kMockFsr, v);
      p.setBool(_kMockEeg, v);
    });
  }

  void setSessionsRoot(String v) {
    sessionsRoot = v;
    _save((p) => p.setString(_kSessionsRoot, v));
  }

  void setProtocolsRoot(String v) {
    protocolsRoot = v;
    _save((p) => p.setString(_kProtocolsRoot, v));
  }

  void setExercisesRoot(String v) {
    exercisesRoot = v;
    _save((p) => p.setString(_kExercisesRoot, v));
  }

  void setWsUri(String v) {
    wsUri = v.trim();
    _save((p) => p.setString(_kWsUri, wsUri));
  }

  void setLastPatientId(String v) {
    lastPatientId = v;
    _save((p) => p.setString(_kLastPatientId, v));
  }

  void setDarkMode(bool v) {
    darkMode = v;
    _save((p) => p.setBool(_kDarkMode, v));
  }

  /// Flattened params for the Unity `configure_session` command.
  Map<String, dynamic> toUnityConfig({
    required String patientId,
    required String exerciseClass,
    required String mode,
  }) =>
      {
        'patientId': patientId,
        'exerciseClass': exerciseClass,
        'mode': mode,
        'zed': zedEnabled,
        'fsr': fsrEnabled,
        'eeg': eegEnabled,
        'fsrConnType': fsrConnType,
        'fsrUsbPort': fsrUsbPort,
        'fsrUri': fsrUri,
        'fsrApiKey': fsrApiKey,
      };
}
