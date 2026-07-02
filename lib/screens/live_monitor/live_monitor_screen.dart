import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/unity_connection_service.dart';
import '../../services/session_repository.dart';
import '../../widgets/sensor_warmup_loader.dart';
import 'panels/top_bar.dart';
import 'panels/motion_tracking_panel.dart';
import 'panels/plantar_pressure_panel.dart';
import 'panels/eeg_panel.dart';
import 'panels/fusion_panel.dart';

/// Live capture view. Every sensor panel can be hidden from the side rail —
/// the 3D avatar (motion panel) absorbs the freed space, and can also be
/// expanded to fill the whole screen.
class LiveMonitorScreen extends StatefulWidget {
  const LiveMonitorScreen({super.key});

  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen> {
  bool _showFsr = true;
  bool _showEeg = true;
  bool _showFusion = true;
  bool _avatarExpanded = false;

  SavedSessionInfo? _lastShownSave;
  bool _savedDialogOpen = false;
  int _lastRecordingSeconds = 0;
  late final UnityConnectionService _conn;

  @override
  void initState() {
    super.initState();
    // Surface "session saved" broadcasts from Unity as a completion dialog
    // with the captured details and next-step actions.
    _conn = context.read<UnityConnectionService>();
    _conn.addListener(_onConnectionEvent);
  }

  @override
  void dispose() {
    // Leaving the live monitor (back button or any navigation) ends the active
    // Unity capture — Unity saves it if recording was started, or just closes
    // the preview otherwise. No-op when not connected.
    _conn.stopRecording();
    _conn.removeListener(_onConnectionEvent);
    super.dispose();
  }

  void _onConnectionEvent() {
    if (!mounted) return;
    // Remember the last live recording duration so the completion dialog can
    // report it (the saved broadcast itself carries no duration).
    final secs = _conn.state.session.recordingSeconds;
    if (secs > 0) _lastRecordingSeconds = secs;

    final saved = _conn.lastSaved;
    if (saved == null || saved == _lastShownSave || _savedDialogOpen) return;
    _lastShownSave = saved;
    _savedDialogOpen = true;
    // Defer to after the current frame: this listener can fire during a build
    // (Unity broadcasts arrive while the panels are rebuilding), and opening a
    // dialog synchronously then throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _savedDialogOpen = false;
        return;
      }
      _showSavedDialog(saved);
    });
  }

  Future<void> _showSavedDialog(SavedSessionInfo saved) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.inkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          const Icon(Icons.check_circle, color: AppColors.accentGreen, size: 22),
          const SizedBox(width: 10),
          Text('Session saved',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.inkText, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _detailRow('Patient', saved.patientId),
            _detailRow('Session', saved.sessionId),
            if (_lastRecordingSeconds > 0)
              _detailRow('Duration', _fmtDuration(_lastRecordingSeconds)),
            _detailRow('Saved to', saved.folder, mono: true),
            const SizedBox(height: 8),
            Text('The capture was written to disk. Record another trial for this patient, or open it now in Replay.',
                style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 11.5)),
          ]),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted)),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                // Back to Home, where a new session for the same patient (the
                // last patient id is retained in settings) can be started.
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
              icon: const Icon(Icons.fiber_manual_record, size: 14),
              label: const Text('Record another'),
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<SessionRepository>().refresh();
                Navigator.of(context).pushReplacementNamed('/replay');
              },
              icon: const Icon(Icons.play_circle_outline, size: 16),
              label: const Text('Open in Replay'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentGreen, foregroundColor: Colors.white),
            ),
          ]),
        ],
      ),
    );
    _savedDialogOpen = false;
  }

  Widget _detailRow(String label, String value, {bool mono = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 78,
            child: Text(label,
                style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 11.5)),
          ),
          Expanded(
            child: Text(value,
                style: mono
                    ? GoogleFonts.robotoMono(color: AppColors.inkText, fontSize: 11)
                    : GoogleFonts.schibstedGrotesk(
                        color: AppColors.inkText, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  static String _fmtDuration(int seconds) {
    final m = seconds ~/ 60, s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<UnityConnectionService>();
    // Connected but no real frame yet → sensors are still warming up. Show the
    // loader and reveal the monitor once data flows. Mocked sensors count as
    // ready, so mock sessions skip the warm-up screen.
    final warming = conn.isConnected && !conn.receivingLive && !conn.anyMock;

    return Scaffold(
      backgroundColor: AppColors.inkBg,
      body: Column(children: [
        const TopBar(),
        const _ConnectionBanner(),
        if (warming)
          const Expanded(child: SensorWarmupLoader())
        else ...[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
            child: Column(children: [
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // ── avatar / motion: always visible, grows as others hide ──
                  Expanded(
                    flex: _avatarExpanded ? 1 : 5,
                    child: _PanelWithTools(
                      mockBadge: conn.mockMotion,
                      tools: [
                        _tool(
                          _avatarExpanded ? Icons.close_fullscreen : Icons.open_in_full,
                          _avatarExpanded ? 'Restore layout' : 'Expand avatar',
                          () => setState(() => _avatarExpanded = !_avatarExpanded),
                        ),
                      ],
                      child: const MotionTrackingPanel(),
                    ),
                  ),
                  if (!_avatarExpanded && _showFsr) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: _PanelWithTools(
                        mockBadge: conn.mockFsr,
                        tools: [
                          _tool(Icons.visibility_off_outlined, 'Hide FSR panel',
                              () => setState(() => _showFsr = false)),
                        ],
                        child: const PlantarPressurePanel(),
                      ),
                    ),
                  ],
                  if (!_avatarExpanded && _showEeg) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: _PanelWithTools(
                        mockBadge: conn.mockEeg,
                        tools: [
                          _tool(Icons.visibility_off_outlined, 'Hide EEG panel',
                              () => setState(() => _showEeg = false)),
                        ],
                        child: const EEGPanel(),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  _SideRail(
                    showFsr: _showFsr,
                    showEeg: _showEeg,
                    showFusion: _showFusion,
                    avatarExpanded: _avatarExpanded,
                    onToggleFsr: () => setState(() {
                      _showFsr = !_showFsr;
                      if (_showFsr) _avatarExpanded = false;
                    }),
                    onToggleEeg: () => setState(() {
                      _showEeg = !_showEeg;
                      if (_showEeg) _avatarExpanded = false;
                    }),
                    onToggleFusion: () => setState(() => _showFusion = !_showFusion),
                    onToggleExpand: () =>
                        setState(() => _avatarExpanded = !_avatarExpanded),
                  ),
                ]),
              ),
              if (!_avatarExpanded && _showFusion) ...[
                const SizedBox(height: 8),
                const SizedBox(height: 184, child: FusionPanel()),
              ],
            ]),
          ),
        ),
        // Status bar
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: const Color(0xFF060F22),
          child: Row(children: [
            _StatusItem(Icons.schedule, _systemTime()),
            const Spacer(),
            _StatusItem(Icons.videocam_outlined, 'Camera: 60 fps'),
            const SizedBox(width: 24),
            _StatusItem(Icons.accessibility, 'Pressure: 100 Hz'),
            const SizedBox(width: 24),
            _StatusItem(Icons.psychology_outlined, 'EEG: 250 Hz'),
            const Spacer(),
            if (conn.anyMock) ...[
              _StatusItem(Icons.science_outlined,
                  'Mock: ${[
                    if (conn.mockMotion) 'Motion',
                    if (conn.mockFsr) 'FSR',
                    if (conn.mockEeg) 'EEG',
                  ].join(', ')}'),
              const SizedBox(width: 16),
            ],
            _StatusItem(Icons.info_outline, 'Research Use Only'),
          ]),
        ),
        ],
      ]),
    );
  }

  Widget _tool(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.inkBorder),
            ),
            child: Icon(icon, size: 13, color: AppColors.inkMuted),
          ),
        ),
      );

  String _systemTime() {
    final now = DateTime.now();
    return 'System Time: ${now.year}-${_p(now.month)}-${_p(now.day)} '
        '${_p(now.hour)}:${_p(now.minute)}:${_p(now.second)}';
  }

  String _p(int v) => v.toString().padLeft(2, '0');
}

/// Overlays small tool buttons (hide / expand) and an optional MOCK badge on
/// top of an existing dashboard panel without modifying the panel itself.
class _PanelWithTools extends StatelessWidget {
  final Widget child;
  final List<Widget> tools;
  final bool mockBadge;
  const _PanelWithTools({required this.child, required this.tools, this.mockBadge = false});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: child),
      Positioned(
        top: 7,
        right: 32, // sits left of the panel's own header icon
        child: Row(children: [
          if (mockBadge)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.5)),
              ),
              child: Text('MOCK',
                  style: GoogleFonts.schibstedGrotesk(
                      color: AppColors.accentOrange,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
            ),
          ...tools,
        ]),
      ),
    ]);
  }
}

/// Thin vertical rail with one toggle per panel — hidden panels stay one
/// click away, and the avatar expand lives here too.
class _SideRail extends StatelessWidget {
  final bool showFsr, showEeg, showFusion, avatarExpanded;
  final VoidCallback onToggleFsr, onToggleEeg, onToggleFusion, onToggleExpand;

  const _SideRail({
    required this.showFsr,
    required this.showEeg,
    required this.showFusion,
    required this.avatarExpanded,
    required this.onToggleFsr,
    required this.onToggleEeg,
    required this.onToggleFusion,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF081224),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inkBorder),
      ),
      child: Column(children: [
        const SizedBox(height: 8),
        _railBtn(Icons.open_in_full, 'Expand avatar', avatarExpanded, onToggleExpand,
            activeColor: AppColors.accent),
        const Divider(color: AppColors.inkBorder, height: 16, indent: 6, endIndent: 6),
        _railBtn(Icons.accessibility, 'FSR pressure panel', showFsr, onToggleFsr,
            activeColor: AppColors.accentCyan),
        const SizedBox(height: 6),
        _railBtn(Icons.psychology_outlined, 'EEG panel', showEeg, onToggleEeg,
            activeColor: const Color(0xFFBB86FC)),
        const SizedBox(height: 6),
        _railBtn(Icons.stacked_line_chart, 'Fusion panel', showFusion, onToggleFusion,
            activeColor: AppColors.accentGreen),
        const Spacer(),
      ]),
    );
  }

  Widget _railBtn(IconData icon, String tip, bool active, VoidCallback onTap,
          {required Color activeColor}) =>
      Tooltip(
        message: '$tip — ${active ? 'click to hide' : 'click to show'}',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: active ? activeColor.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                  color: active ? activeColor.withValues(alpha: 0.5) : AppColors.inkBorder),
            ),
            child: Icon(icon, size: 14, color: active ? activeColor : AppColors.inkMuted),
          ),
        ),
      );
}

// Shows a prominent bar whenever the dashboard is NOT receiving live Unity data.
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<UnityConnectionService>();
    if (svc.isConnected) return const SizedBox.shrink();

    final connecting = svc.connectionState == UnityConnectionStatus.connecting;
    final color = connecting
        ? AppColors.accentOrange
        : svc.anyMock
            ? AppColors.accentOrange
            : AppColors.accentRed;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: color.withValues(alpha: 0.12),
      child: Row(children: [
        Icon(connecting ? Icons.sync : (svc.anyMock ? Icons.science_outlined : Icons.link_off),
            size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            connecting
                ? 'Connecting to Unity…'
                : svc.anyMock
                    ? 'Mock data — not connected to Unity. Mocked sensors animate locally; connect to see real data.'
                    : 'Disconnected from Unity${svc.error.isNotEmpty ? ' — ${svc.error}' : ''}. Reconnecting…',
            style: GoogleFonts.schibstedGrotesk(color: AppColors.inkText, fontSize: 11),
          ),
        ),
        const SizedBox(width: 12),
        if (!connecting)
          ElevatedButton.icon(
            onPressed: () => svc.connect(),
            icon: const Icon(Icons.link, size: 14),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: const Size(0, 28),
              textStyle: GoogleFonts.schibstedGrotesk(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            label: const Text('Connect'),
          ),
      ]),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _StatusItem(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 10, color: AppColors.inkMuted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: AppColors.inkMuted, fontSize: 9)),
      ]);
}
