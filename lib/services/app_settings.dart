import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/avatar_style.dart';
import '../models/serial_port_info.dart';

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
  static const _kEegComPort = 'eeg_com_port';
  static const _kMockMotion = 'mock_motion';
  static const _kMockFsr = 'mock_fsr';
  static const _kMockEeg = 'mock_eeg';
  static const _kSessionsRoot = 'sessions_root';
  static const _kProtocolsRoot = 'protocols_root';
  static const _kExercisesRoot = 'exercises_root';
  static const _kParticipantsRoot = 'participants_root';
  static const _kWsUri = 'ws_uri';
  static const _kLastPatientId = 'last_patient_id';
  static const _kDarkMode = 'dark_mode';
  static const _kAvatarStyle = 'avatar_style';
  static const _kOnboardingSeen = 'onboarding_seen';

  SharedPreferences? _prefs;

  String fsrConnType = 'Mock';
  String fsrUsbPort = '';
  String fsrUri = '';
  String fsrApiKey = '';

  bool zedEnabled = true;
  bool fsrEnabled = true;
  bool eegEnabled = false;
  String eegComPort = '';

  // Dashboard-side mock data, per sensor. Lets you test the live view and
  // replay without hardware — mocked sensors animate locally while any
  // non-mocked sensor still shows real Unity data.
  bool mockMotion = false;
  bool mockFsr = false;
  bool mockEeg = false;

  String sessionsRoot = '';
  String protocolsRoot = '';
  String exercisesRoot = '';
  String participantsRoot = '';
  String wsUri = 'ws://localhost:8765';
  String lastPatientId = '';
  bool darkMode = false;
  AvatarStyle avatarStyle = AvatarStyle.lines;
  bool onboardingSeen = false;

  /// Currently-present serial ports, richest-first metadata. Phantom ports left
  /// behind by an earlier Bluetooth pairing are filtered out (see [refreshPorts]).
  List<SerialPortInfo> ports = [];

  /// Bare port names, for callers that only need the identifier (FSR picker,
  /// the value pushed to Unity). Backed by [ports].
  List<String> get availablePorts => ports.map((p) => p.port).toList();

  /// The port that unambiguously looks like the paired Unicorn headset — the
  /// single *bound* Bluetooth SPP port. Null when there are zero or several
  /// candidates (nothing to safely auto-pick). Drives the EEG picker's suggestion.
  SerialPortInfo? get suggestedEegPort {
    final bound = ports.where((p) => p.isBoundBluetooth).toList();
    return bound.length == 1 ? bound.first : null;
  }

  /// The port that looks like the USB FSR insole board — a single USB-serial
  /// (Arduino) port. Null when there are zero or several candidates. Drives the
  /// FSR picker's ★ suggestion and auto-select.
  SerialPortInfo? get suggestedFsrPort {
    final usb = ports.where((p) => p.isUsbSerial).toList();
    return usb.length == 1 ? usb.first : null;
  }

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

  /// The pseudonymous participant registry lives in a sibling `Participants`
  /// folder by default (codes + consent status only — never identities).
  static String defaultParticipantsRoot() {
    final home = Platform.environment['USERPROFILE'] ?? '';
    return '$home\\AppData\\LocalLow\\DefaultCompany\\Smart Game\\Participants';
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
    eegComPort = p.getString(_kEegComPort) ?? '';
    mockMotion = p.getBool(_kMockMotion) ?? false;
    mockFsr = p.getBool(_kMockFsr) ?? false;
    mockEeg = p.getBool(_kMockEeg) ?? false;
    sessionsRoot = p.getString(_kSessionsRoot) ?? defaultSessionsRoot();
    protocolsRoot = p.getString(_kProtocolsRoot) ?? defaultProtocolsRoot();
    exercisesRoot = p.getString(_kExercisesRoot) ?? defaultExercisesRoot();
    participantsRoot = p.getString(_kParticipantsRoot) ?? defaultParticipantsRoot();
    wsUri = p.getString(_kWsUri) ?? 'ws://localhost:8765';
    lastPatientId = p.getString(_kLastPatientId) ?? '';
    darkMode = p.getBool(_kDarkMode) ?? false;
    avatarStyle = AvatarStyleInfo.fromToken(p.getString(_kAvatarStyle));
    onboardingSeen = p.getBool(_kOnboardingSeen) ?? false;
    notifyListeners();
    refreshPorts();
  }

  /// PowerShell that enumerates every COM port via `Win32_PnPEntity`, emitting
  /// one tab-safe line per port: `COMx|~|<friendly name>|~|<present 0/1>|~|<pnpId>`.
  /// This gives us the friendly name and PnP id `GetPortNames()` lacks, so the
  /// picker can label ports and spot the paired headset, and `Present` lets us
  /// drop phantom ports a re-pair left behind. A null `Present` is treated as
  /// present (only an explicit `false` marks a port absent).
  static const _kPortQuery =
      r"$ErrorActionPreference='SilentlyContinue';"
      r"Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match '\(COM\d+\)' } | "
      r"ForEach-Object { "
      r"$com=[regex]::Match($_.Name,'\((COM\d+)\)').Groups[1].Value; "
      r"$p= if ($_.Present -eq $false) {'0'} else {'1'}; "
      r"($com + '|~|' + $_.Name + '|~|' + $p + '|~|' + $_.PNPDeviceID) }";

  /// Enumerate serial ports, keeping only ports currently present and sorted by
  /// COM number. Prefers the rich `Win32_PnPEntity` query; falls back to Unity's
  /// own `SerialPort.GetPortNames()` (bare names) if that is unavailable. When
  /// the paired headset can be identified unambiguously and no valid EEG port is
  /// selected yet, it is auto-selected so the clinician needn't guess.
  Future<void> refreshPorts() async {
    final all = await _enumeratePorts();
    ports = all.where((p) => p.present).toList()
      ..sort((a, b) => _comNumber(a.port).compareTo(_comNumber(b.port)));

    final names = ports.map((p) => p.port).toSet();
    final suggestion = suggestedEegPort;
    if (suggestion != null && !names.contains(eegComPort)) {
      eegComPort = suggestion.port;
      _prefs?.setString(_kEegComPort, eegComPort);
    }
    // Same for the FSR: auto-pick the USB (Arduino) port when the saved one is
    // gone/empty. An explicit, still-present choice is left untouched.
    final fsrSuggestion = suggestedFsrPort;
    if (fsrSuggestion != null && !names.contains(fsrUsbPort)) {
      fsrUsbPort = fsrSuggestion.port;
      _prefs?.setString(_kFsrUsbPort, fsrUsbPort);
    }
    notifyListeners();
  }

  Future<List<SerialPortInfo>> _enumeratePorts() async {
    // Preferred: friendly name + PnP id + present flag.
    try {
      final r = await Process.run(
          'powershell', ['-NoProfile', '-Command', _kPortQuery]);
      final out = (r.stdout as String).trim();
      if (out.isNotEmpty) {
        final list = <SerialPortInfo>[];
        for (final line in out.split(RegExp(r'\r?\n'))) {
          final f = line.split('|~|');
          if (f.length < 4 || f[0].trim().isEmpty) continue;
          list.add(SerialPortInfo(
            port: f[0].trim(),
            friendlyName: f[1].trim(),
            present: f[2].trim() != '0',
            pnpId: f[3].trim(),
          ));
        }
        if (list.isNotEmpty) return list;
      }
    } catch (_) {/* fall through to bare-name enumeration */}

    // Fallback: bare port names, the same way Unity enumerates them.
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '[System.IO.Ports.SerialPort]::GetPortNames() -join ","',
      ]);
      final out = (r.stdout as String).trim();
      if (out.isEmpty) return [];
      return out
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map(SerialPortInfo.bare)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Numeric part of a `COMx` name, for natural sorting (COM9 before COM10).
  static int _comNumber(String port) =>
      int.tryParse(port.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

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

  void setEegComPort(String v) {
    eegComPort = v;
    _save((p) => p.setString(_kEegComPort, v));
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

  void setParticipantsRoot(String v) {
    participantsRoot = v;
    _save((p) => p.setString(_kParticipantsRoot, v));
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

  void setAvatarStyle(AvatarStyle v) {
    avatarStyle = v;
    _save((p) => p.setString(_kAvatarStyle, v.token));
  }

  void setOnboardingSeen(bool v) {
    onboardingSeen = v;
    _save((p) => p.setBool(_kOnboardingSeen, v));
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
        'eegComPort': eegComPort,
        'fsrConnType': fsrConnType,
        'fsrUsbPort': fsrUsbPort,
        'fsrUri': fsrUri,
        'fsrApiKey': fsrApiKey,
      };
}
