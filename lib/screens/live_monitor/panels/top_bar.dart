import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../services/unity_connection_service.dart';
import '../../../theme/app_theme.dart';

class TopBar extends StatefulWidget {
  const TopBar({super.key});

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<UnityConnectionService>();
    final s = svc.state;

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF060F22),
        border: Border(bottom: BorderSide(color: AppColors.inkBorder)),
      ),
      child: Row(children: [
        // ── Back button ─────────────────────────────────────────────────
        Tooltip(
          message: 'Back to Home',
          child: InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: AppColors.inkSurfaceAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.inkBorder),
              ),
              child: const Icon(Icons.arrow_back, color: AppColors.inkText, size: 16),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Icon + short title
        const Icon(Icons.psychology, color: AppColors.accent, size: 18),
        const SizedBox(width: 6),
        Flexible(
          flex: 2,
          child: Text('Multimodal Telerehab Monitor',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkText, fontSize: 13, fontWeight: FontWeight.w600,
              )),
        ),

        const SizedBox(width: 12),

        // Session info chips
        _InfoChip('ID', s.session.participantId),
        const SizedBox(width: 6),
        _InfoChip('Ses', s.session.sessionNumber.toString().padLeft(2, '0')),
        const SizedBox(width: 6),
        _InfoChip('Trial', s.session.trialNumber.toString().padLeft(2, '0')),
        const SizedBox(width: 6),
        Flexible(
          child: _InfoChip('Cond', s.session.condition, color: AppColors.accent),
        ),

        const Spacer(),

        // Recording / standby indicator
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            // Connected but no real frame yet = sensors still warming up.
            final warming = svc.isConnected && !svc.receivingLive;
            final rec = s.session.isRecording;
            final paused = s.session.isPaused;
            final (Color dotColor, Color textColor, String label) = warming
                ? (AppColors.accentOrange, AppColors.accentOrange,
                    'Warming up sensors…')
                : !rec
                    ? (AppColors.inkMuted, AppColors.inkMuted,
                        'Standby — press ● to record')
                    : paused
                        ? (AppColors.accentOrange, AppColors.accentOrange,
                            'Paused  ${_formatTime(s.session.recordingSeconds)}')
                        : (AppColors.accentRed, AppColors.inkText,
                            'Recording  ${_formatTime(s.session.recordingSeconds)}');
            final pulsing = warming || (rec && !paused);
            return Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Pulse while warming up or actively recording; solid otherwise.
                  color: pulsing
                      ? dotColor.withValues(alpha: 0.4 + 0.6 * _pulse.value)
                      : dotColor.withValues(alpha: rec ? 1 : 0.4),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.schibstedGrotesk(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ]);
          },
        ),

        const SizedBox(width: 16),

        // Recording controls — these drive the Unity capture session
        _IconBtn(Icons.fiber_manual_record, 'Start recording', AppColors.accentGreen,
          svc.startRecording),
        const SizedBox(width: 4),
        _IconBtn(Icons.pause, 'Pause recording', AppColors.accentOrange,
          svc.pauseRecording),
        const SizedBox(width: 4),
        _IconBtn(Icons.stop, 'Stop & save session', AppColors.accentRed,
          svc.stopRecording),
        const SizedBox(width: 4),
        _IconBtn(Icons.flag_outlined, 'Mark event', AppColors.inkMuted,
          svc.markEvent),

        const SizedBox(width: 12),

        // Sensor status (compact: icon + dot only)
        _SensorChip(Icons.videocam_outlined, 'Cam', s.sensors.camera),
        const SizedBox(width: 4),
        _SensorChip(Icons.directions_walk, 'FSR', s.sensors.pressureInsole),
        const SizedBox(width: 4),
        _SensorChip(Icons.psychology_outlined, 'EEG', s.sensors.eeg),

        const SizedBox(width: 8),

        // Connection status + settings
        _ConnectionDot(svc),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.more_vert, color: AppColors.inkMuted, size: 18),
          onPressed: () => _showConnectionDialog(context, svc),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
      ]),
    );
  }

  void _showConnectionDialog(BuildContext ctx, UnityConnectionService svc) {
    final controller = TextEditingController(text: 'ws://localhost:8765');
    showDialog(context: ctx, builder: (dialogCtx) => AlertDialog(
      backgroundColor: AppColors.inkSurface,
      title: Text('Unity Connection', style: GoogleFonts.schibstedGrotesk(color: AppColors.inkText)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: controller,
          style: GoogleFonts.schibstedGrotesk(color: AppColors.inkText),
          decoration: InputDecoration(
            labelText: 'WebSocket URL',
            labelStyle: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          TextButton(
            onPressed: () { Navigator.pop(dialogCtx); svc.enableDemoMode(); },
            child: Text('Demo Mode', style: GoogleFonts.schibstedGrotesk(color: AppColors.accentOrange)),
          ),
          ElevatedButton(
            onPressed: () async { Navigator.pop(dialogCtx); await svc.connect(controller.text); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            child: Text('Connect', style: GoogleFonts.schibstedGrotesk(color: Colors.white)),
          ),
        ]),
      ]),
    ));
  }

  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return h > 0
      ? '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}'
      : '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _InfoChip(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 9)),
      Text(value, style: GoogleFonts.schibstedGrotesk(
        color: color ?? AppColors.inkText, fontSize: 13, fontWeight: FontWeight.w600,
      )),
    ],
  );
}

// Compact icon-only button with tooltip
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  const _IconBtn(this.icon, this.tooltip, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    ),
  );
}

class _SensorChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool connected;
  const _SensorChip(this.icon, this.label, this.connected);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: (connected ? AppColors.accentGreen : AppColors.accentRed).withOpacity(0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: (connected ? AppColors.accentGreen : AppColors.accentRed).withOpacity(0.3),
      ),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: connected ? AppColors.accentGreen : AppColors.accentRed),
      const SizedBox(width: 4),
      Text(label, style: GoogleFonts.schibstedGrotesk(
        color: connected ? AppColors.accentGreen : AppColors.accentRed,
        fontSize: 10, fontWeight: FontWeight.w500,
      )),
      const SizedBox(width: 4),
      Text(connected ? 'Connected' : 'Offline',
        style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 9)),
    ]),
  );
}

class _ConnectionDot extends StatelessWidget {
  final UnityConnectionService svc;
  const _ConnectionDot(this.svc);

  @override
  Widget build(BuildContext context) {
    final (color, tip) = switch (svc.connectionState) {
      UnityConnectionStatus.connected    => (AppColors.accentGreen, 'Unity connected'),
      UnityConnectionStatus.connecting   => (AppColors.accentOrange, 'Connecting…'),
      UnityConnectionStatus.disconnected => (AppColors.inkMuted, 'Demo mode'),
      UnityConnectionStatus.error        => (AppColors.accentRed, 'Connection error'),
    };
    return Tooltip(message: tip, child: Container(
      width: 8, height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ));
  }
}
