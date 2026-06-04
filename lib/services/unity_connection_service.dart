import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/telerehab_state.dart';

enum UnityConnectionStatus { disconnected, connecting, connected, error }

class UnityConnectionService extends ChangeNotifier {
  static const _defaultUri = 'ws://localhost:8765';

  WebSocketChannel? _channel;
  UnityConnectionStatus _connectionState = UnityConnectionStatus.disconnected;
  TelerehabState _state = TelerehabState.demo;
  String _error = '';
  Timer? _reconnectTimer;
  Timer? _demoTimer;
  bool _useDemoMode = true;

  UnityConnectionStatus get connectionState => _connectionState;
  TelerehabState get state => _state;
  String get error => _error;
  bool get isConnected => _connectionState == UnityConnectionStatus.connected;
  bool get useDemoMode => _useDemoMode;

  String _lastUri = _defaultUri;

  /// Async connect — awaits [WebSocketChannel.ready] so failures are caught
  /// cleanly instead of crashing with an unhandled exception.
  Future<void> connect([String uri = _defaultUri]) async {
    _lastUri = uri;
    _useDemoMode = false;
    _stopDemo();
    _stopReconnect();

    // Close any previous channel first
    await _channel?.sink.close();
    _channel = null;

    _setUnityConnectionStatus(UnityConnectionStatus.connecting);

    try {
      final channel = WebSocketChannel.connect(Uri.parse(uri));

      // .ready throws WebSocketChannelException if the server is not up
      await channel.ready;

      _channel = channel;
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      _setUnityConnectionStatus(UnityConnectionStatus.connected);
    } catch (e) {
      _channel = null;
      _error = _friendlyError(e);
      _setUnityConnectionStatus(UnityConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _useDemoMode = false;
    _stopReconnect();
    _channel?.sink.close();
    _channel = null;
    _setUnityConnectionStatus(UnityConnectionStatus.disconnected);
  }

  void enableDemoMode() {
    _useDemoMode = true;
    disconnect();
    _startDemo();
  }

  void sendCommand(UnityCommand cmd) {
    if (_channel != null && isConnected) {
      _channel!.sink.add(cmd.toJson());
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      if (json['type'] == 'sensor_update') {
        _state = TelerehabState.fromJson(json);
        notifyListeners();
      }
    } catch (_) {}
  }

  void _onError(dynamic e) {
    _error = _friendlyError(e);
    _channel = null;
    _setUnityConnectionStatus(UnityConnectionStatus.error);
    _scheduleReconnect();
  }

  void _onDone() {
    _channel = null;
    _setUnityConnectionStatus(UnityConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_useDemoMode) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(seconds: 3),
      () => connect(_lastUri),
    );
  }

  void _stopReconnect() => _reconnectTimer?.cancel();

  static String _friendlyError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('Connection refused') || msg.contains('not upgraded'))
      return 'Unity is not running — start Unity first';
    if (msg.contains('SocketException'))
      return 'Cannot reach Unity — check that it is running';
    return msg;
  }

  // ── Demo mode: animate fake data so the UI is always live-looking ──
  double _demoAngle = 52;
  double _demoDir = 1;
  int _demoSeconds = 462;

  void _startDemo() {
    _state = TelerehabState.demo;
    _demoTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _demoAngle += _demoDir * 0.8;
      if (_demoAngle > 75) _demoDir = -1;
      if (_demoAngle < 30) _demoDir = 1;
      _demoSeconds++;

      final pressureHistory = List<double>.from(_state.pressureHistory);
      pressureHistory.add(60 + 15 * (_demoAngle / 75));
      if (pressureHistory.length > 80) pressureHistory.removeAt(0);

      _state = TelerehabState(
        session: SessionInfo(
          participantId: _state.session.participantId,
          sessionNumber: _state.session.sessionNumber,
          trialNumber: _state.session.trialNumber,
          condition: _state.session.condition,
          recordingSeconds: _demoSeconds,
          isRecording: true,
        ),
        jointAngles: [
          JointAngleData(
            name: 'Knee Angle', angle: _demoAngle,
            deviation: _demoAngle - 52,
            targetMin: 40, targetMax: 60,
            repCount: (_demoSeconds ~/ 200) % 11,
            targetReps: 10,
            trackingConfidence: 1.0,
            trunkLean: 2 + (_demoAngle / 75) * 4,
          ),
          JointAngleData(
            name: 'Hip Angle', angle: 88 + (_demoAngle - 52) * 0.4,
            deviation: (_demoAngle - 52) * 0.4,
            targetMin: 80, targetMax: 100,
          ),
        ],
        plantar: PlantarData(
          leftFoot:  List.generate(16, (i) => (PlantarData.demo.leftFoot[i] * (0.8 + _demoDir * 0.1)).clamp(0, 1)),
          rightFoot: List.generate(16, (i) => (PlantarData.demo.rightFoot[i] * (0.8 - _demoDir * 0.1)).clamp(0, 1)),
          totalLoad:   60 + 15 * (_demoAngle / 75),
          heelLoad:    30 + 5 * (_demoAngle / 75),
          forefootLoad:30 + 10 * (_demoAngle / 75),
          asymmetry:   8 + 2 * _demoDir,
          stability:   0.5 + 0.3 * (_demoAngle / 75),
        ),
        sensors: const SensorStatus(camera: true, pressureInsole: true, eeg: true),
        pressureHistory: pressureHistory,
      );
      notifyListeners();
    });
  }

  void _stopDemo() => _demoTimer?.cancel();

  void _setUnityConnectionStatus(UnityConnectionStatus s) {
    _connectionState = s;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _stopDemo();
    super.dispose();
  }
}
