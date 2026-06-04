import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../services/unity_connection_service.dart';
import '../../../models/telerehab_state.dart';
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
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        // Icon + short title
        const Icon(Icons.hub, color: AppColors.accent, size: 18),
        const SizedBox(width: 6),
        Flexible(
          flex: 2,
          child: Text('TeleRehab Monitor',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600,
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

        // Recording timer
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Row(children: [
            if (s.session.isRecording) ...[
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentRed.withOpacity(0.4 + 0.6 * _pulse.value),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              'Recording  ${_formatTime(s.session.recordingSeconds)}',
              style: GoogleFonts.inter(
                color: s.session.isRecording ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 13, fontWeight: FontWeight.w500,
              ),
            ),
          ]),
        ),

        const SizedBox(width: 16),

        // Control buttons (icon-only with tooltip to save space)
        _IconBtn(Icons.play_arrow, 'Start',      AppColors.accent,
          () => svc.sendCommand(UnityCommand('start_recording'))),
        const SizedBox(width: 4),
        _IconBtn(Icons.stop,       'Stop',       AppColors.accentRed,
          () => svc.sendCommand(UnityCommand('stop_recording'))),
        const SizedBox(width: 4),
        _IconBtn(Icons.pause,      'Pause',      AppColors.accentOrange,
          () => svc.sendCommand(UnityCommand('pause_recording'))),
        const SizedBox(width: 4),
        _IconBtn(Icons.flag_outlined, 'Mark Event', AppColors.textSecondary,
          () => svc.sendCommand(UnityCommand('mark_event'))),

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
          icon: const Icon(Icons.more_vert, color: AppColors.textSecondary, size: 18),
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
      backgroundColor: AppColors.surface,
      title: Text('Unity Connection', style: GoogleFonts.inter(color: AppColors.textPrimary)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: controller,
          style: GoogleFonts.inter(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'WebSocket URL',
            labelStyle: GoogleFonts.inter(color: AppColors.textSecondary),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          TextButton(
            onPressed: () { Navigator.pop(dialogCtx); svc.enableDemoMode(); },
            child: Text('Demo Mode', style: GoogleFonts.inter(color: AppColors.accentOrange)),
          ),
          ElevatedButton(
            onPressed: () async { Navigator.pop(dialogCtx); await svc.connect(controller.text); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            child: Text('Connect', style: GoogleFonts.inter(color: Colors.white)),
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
      Text(label, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 9)),
      Text(value, style: GoogleFonts.inter(
        color: color ?? AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600,
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
      Text(label, style: GoogleFonts.inter(
        color: connected ? AppColors.accentGreen : AppColors.accentRed,
        fontSize: 10, fontWeight: FontWeight.w500,
      )),
      const SizedBox(width: 4),
      Text(connected ? 'Connected' : 'Offline',
        style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 9)),
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
      UnityConnectionStatus.disconnected => (AppColors.textSecondary, 'Demo mode'),
      UnityConnectionStatus.error        => (AppColors.accentRed, 'Connection error'),
    };
    return Tooltip(message: tip, child: Container(
      width: 8, height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ));
  }
}
