import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/telerehab_state.dart';
import 'mock_sensors.dart';

enum UnityConnectionStatus { disconnected, connecting, connected, error }

/// Info broadcast by Unity after SessionWriter finishes a capture.
class SavedSessionInfo {
  final String patientId;
  final String sessionId;
  final String folder;
  final DateTime receivedAt;
  const SavedSessionInfo({
    required this.patientId,
    required this.sessionId,
    required this.folder,
    required this.receivedAt,
  });
}

/// WebSocket link to the Unity engine plus the per-sensor mock overlay.
///
/// Mocking is per sensor: with `mockFsr` on but `mockMotion` off, the plantar
/// panels animate from [MockSensors] while the skeleton still shows whatever
/// Unity streams. With every sensor mocked the dashboard is fully usable
/// without Unity running.
class UnityConnectionService extends ChangeNotifier {
  static const _defaultUri = 'ws://localhost:8765';

  WebSocketChannel? _channel;
  UnityConnectionStatus _connectionState = UnityConnectionStatus.disconnected;
  TelerehabState _live = TelerehabState.demo; // last state received from Unity
  TelerehabState _state = TelerehabState.demo; // composited (live + mocks)
  String _error = '';
  Timer? _reconnectTimer;
  Timer? _mockTimer;
  double _mockClock = 0;
  final List<double> _mockPressureHistory = [];

  bool _mockMotion = false;
  bool _mockFsr = false;
  bool _mockEeg = false;

  /// True once a real sensor_update has arrived since the last connect/configure
  /// — i.e. the Unity capture scene finished warming up and is now streaming.
  bool _liveFrameSeen = false;

  SavedSessionInfo? lastSaved;
  bool unityReady = false;

  /// Invoked when Unity replies to a clock-sync ping. [unityRecMs] is Unity's
  /// record-clock time in ms at the moment it handled the ping, or -1 if it
  /// wasn't recording yet. Lets a protocol run measure the Flutter↔Unity clock
  /// offset and align marker timestamps to the recorded sensor timeline.
  void Function(int pingId, int unityRecMs)? onPong;

  UnityConnectionStatus get connectionState => _connectionState;
  TelerehabState get state => _state;
  String get error => _error;
  bool get isConnected => _connectionState == UnityConnectionStatus.connected;
  bool get anyMock => _mockMotion || _mockFsr || _mockEeg;
  bool get mockMotion => _mockMotion;
  bool get mockFsr => _mockFsr;
  bool get mockEeg => _mockEeg;

  /// Whether Unity has streamed at least one real frame since the last
  /// connect / configure_session (i.e. sensor warm-up is complete). Resets when
  /// a new session is configured so each run re-detects warm-up.
  bool get receivingLive => _liveFrameSeen;

  /// Back-compat alias used by older UI code: "demo mode" now means
  /// "all sensors mocked and not connected".
  bool get useDemoMode => !isConnected && _mockMotion && _mockFsr && _mockEeg;

  String _lastUri = _defaultUri;

  // ── connection ─────────────────────────────────────────────────────────────

  Future<void> connect([String uri = _defaultUri]) async {
    _lastUri = uri;
    _liveFrameSeen = false;
    _stopReconnect();

    await _channel?.sink.close();
    _channel = null;

    _setStatus(UnityConnectionStatus.connecting);

    try {
      final channel = WebSocketChannel.connect(Uri.parse(uri));
      await channel.ready; // throws if the server is not up

      _channel = channel;
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      _setStatus(UnityConnectionStatus.connected);
    } catch (e) {
      _channel = null;
      _error = _friendlyError(e);
      _setStatus(UnityConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _stopReconnect();
    _channel?.sink.close();
    _channel = null;
    unityReady = false;
    _setStatus(UnityConnectionStatus.disconnected);
  }

  // ── mock control ───────────────────────────────────────────────────────────

  void setMocks({bool? motion, bool? fsr, bool? eeg}) {
    _mockMotion = motion ?? _mockMotion;
    _mockFsr = fsr ?? _mockFsr;
    _mockEeg = eeg ?? _mockEeg;
    _syncMockTimer();
    _recompose();
  }

  /// All sensors mocked, no Unity needed (legacy entry point).
  void enableDemoMode() {
    disconnect();
    setMocks(motion: true, fsr: true, eeg: true);
  }

  void _syncMockTimer() {
    if (anyMock && _mockTimer == null) {
      _mockTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _mockClock += 0.1;
        _recompose();
      });
    } else if (!anyMock && _mockTimer != null) {
      _mockTimer!.cancel();
      _mockTimer = null;
    }
  }

  // ── outgoing commands ──────────────────────────────────────────────────────

  void sendCommand(UnityCommand cmd) {
    if (_channel != null && isConnected) {
      _channel!.sink.add(cmd.toJson());
    }
  }

  /// Push session + sensor configuration into Unity (PlayerPrefs + pending
  /// SessionContext). Flat params parsed by Unity's JsonUtility DTO.
  void configureSession(Map<String, dynamic> config) {
    _liveFrameSeen = false; // new session → wait for warm-up again
    sendCommand(UnityCommand('configure_session', config));
  }

  /// Start the configured capture: Unity fills SessionContext, creates the
  /// session folder and loads the capture scene.
  void startSession() => sendCommand(UnityCommand('start_session'));

  void startRecording() => sendCommand(UnityCommand('start_recording'));
  void stopRecording() => sendCommand(UnityCommand('stop_recording'));
  void pauseRecording() => sendCommand(UnityCommand('pause_recording'));
  void markEvent() => sendCommand(UnityCommand('mark_event'));

  /// Clock-sync ping — Unity echoes [pingId] in a `pong` with its record-clock
  /// time (see [onPong]). Cheap; safe to call several times per run.
  void sendPing(int pingId) => sendCommand(UnityCommand('ping', {'pingId': pingId}));

  // ── incoming ───────────────────────────────────────────────────────────────

  void _onMessage(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (json['type']) {
        case 'sensor_update':
          _live = TelerehabState.fromJson(json);
          _liveFrameSeen = true; // warm-up complete — real data flowing
          _recompose();
          break;
        case 'session_saved':
          lastSaved = SavedSessionInfo(
            patientId: json['patientId'] ?? '',
            sessionId: json['sessionId'] ?? '',
            folder: json['folder'] ?? '',
            receivedAt: DateTime.now(),
          );
          notifyListeners();
          break;
        case 'pong':
          onPong?.call(
            (json['pingId'] as num?)?.toInt() ?? 0,
            (json['unityRecMs'] as num?)?.toInt() ?? -1,
          );
          break;
        case 'heartbeat':
          if (!unityReady) {
            unityReady = true;
            notifyListeners();
          }
          break;
      }
    } catch (_) {}
  }

  /// Merge the latest live state with whichever sensors are mocked.
  void _recompose() {
    var base = _live;

    List<JointAngleData> joints = base.jointAngles;
    var skeleton = base.skeleton;
    var plantar = base.plantar;
    var history = base.pressureHistory;
    var sensors = base.sensors;
    var session = base.session;
    var eeg = base.eeg;

    if (_mockEeg) eeg = MockSensors.eegAt(_mockClock);

    if (_mockMotion) {
      skeleton = MockSensors.skeletonAt(_mockClock);
      joints = [
        MockSensors.kneeJointAt(_mockClock),
        JointAngleData(
          name: 'Hip Angle',
          angle: 88 + (50 - MockSensors.kneeAngleAt(_mockClock)) * 0.3,
          deviation: 0,
          targetMin: 80,
          targetMax: 100,
        ),
      ];
    }
    if (_mockFsr) {
      plantar = MockSensors.plantarAt(_mockClock);
      _mockPressureHistory.add(plantar.totalLoad);
      if (_mockPressureHistory.length > 80) _mockPressureHistory.removeAt(0);
      history = List<double>.from(_mockPressureHistory);
    }
    if (_mockMotion || _mockFsr || _mockEeg) {
      sensors = SensorStatus(
        camera: _mockMotion || sensors.camera,
        pressureInsole: _mockFsr || sensors.pressureInsole,
        eeg: _mockEeg || sensors.eeg,
      );
      if (!isConnected) {
        session = SessionInfo(
          participantId: session.participantId,
          sessionNumber: session.sessionNumber,
          trialNumber: session.trialNumber,
          condition: session.condition,
          recordingSeconds: _mockClock.round(),
          isRecording: true,
        );
      }
    }

    _state = TelerehabState(
      session: session,
      jointAngles: joints,
      plantar: plantar,
      sensors: sensors,
      pressureHistory: history,
      skeleton: skeleton,
      eeg: eeg,
    );
    notifyListeners();
  }

  void _onError(dynamic e) {
    _error = _friendlyError(e);
    _channel = null;
    unityReady = false;
    _setStatus(UnityConnectionStatus.error);
    _scheduleReconnect();
  }

  void _onDone() {
    _channel = null;
    unityReady = false;
    _setStatus(UnityConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(seconds: 3),
      () => connect(_lastUri),
    );
  }

  void _stopReconnect() => _reconnectTimer?.cancel();

  static String _friendlyError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('Connection refused') || msg.contains('not upgraded')) {
      return 'Unity is not running — start Unity first';
    }
    if (msg.contains('SocketException')) {
      return 'Cannot reach Unity — check that it is running';
    }
    return msg;
  }

  void _setStatus(UnityConnectionStatus s) {
    _connectionState = s;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _mockTimer?.cancel();
    super.dispose();
  }
}
