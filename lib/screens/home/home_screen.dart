import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/unity_connection_service.dart';
import '../../services/unity_launch_service.dart';
import '../../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    context.read<UnityLaunchService>().init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF050E1F), Color(0xFF0A1628), Color(0xFF0D2040)],
          ),
        ),
        child: SafeArea(
          child: Row(children: [
            // ── Left column: branding + nav ──────────────────────────────
            SizedBox(
              width: 320,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Logo(),
                    const SizedBox(height: 8),
                    Text(
                      'Multimodal Telerehabilitation\nMonitoring Platform',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 13,
                      ),
                    ).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 40),
                    _NavCard(
                      icon: Icons.monitor_heart_outlined,
                      title: 'Live Monitor',
                      subtitle: 'Real-time session view\nlinked to Unity engine',
                      color: AppColors.accent, route: '/monitor', delay: 0,
                    ),
                    const Spacer(),
                    Text('v1.0.0 • Research Use Only',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 10)),
                  ],
                ),
              ),
            ),

            // ── Right column: Unity launcher ─────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  Expanded(child: _UnityLaunchPanel()),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Branding ─────────────────────────────────────────────────────────────────
class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.accent.withOpacity(0.4)),
        ),
        child: const Icon(Icons.accessibility_new, color: AppColors.accent, size: 22),
      ),
      const SizedBox(width: 10),
      Text('TeleRehab', style: GoogleFonts.inter(
        color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700,
      )),
    ],
  ).animate().fadeIn().slideY(begin: -0.2);
}

// ── Nav card ──────────────────────────────────────────────────────────────────
class _NavCard extends StatefulWidget {
  final IconData icon;
  final String title, subtitle, route;
  final Color color;
  final int delay;
  const _NavCard({required this.icon, required this.title, required this.subtitle,
    required this.color, required this.route, required this.delay});
  @override State<_NavCard> createState() => _NavCardState();
}

class _NavCardState extends State<_NavCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: () => Navigator.pushNamed(context, widget.route),
      child: AnimatedContainer(
        duration: 150.ms,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.surfaceLight : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered ? widget.color.withOpacity(0.5) : AppColors.border,
            width: _hovered ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Icon(widget.icon, color: widget.color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: GoogleFonts.inter(
              color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600,
            )),
            Text(widget.subtitle, style: GoogleFonts.inter(
              color: AppColors.textSecondary, fontSize: 10,
            )),
          ])),
          Icon(Icons.chevron_right, color: widget.color.withOpacity(0.6), size: 16),
        ]),
      ),
    ),
  ).animate().fadeIn(delay: Duration(milliseconds: widget.delay + 300)).slideX(begin: -0.1);
}

// ── Unity Launch Panel ────────────────────────────────────────────────────────
class _UnityLaunchPanel extends StatefulWidget {
  @override State<_UnityLaunchPanel> createState() => _UnityLaunchPanelState();
}

class _UnityLaunchPanelState extends State<_UnityLaunchPanel> {
  Timer? _connectRetry;
  bool _autoConnecting = false;

  @override
  void dispose() {
    _connectRetry?.cancel();
    super.dispose();
  }

  Future<void> _launchAndConnect() async {
    final launcher = context.read<UnityLaunchService>();
    final conn     = context.read<UnityConnectionService>();

    final ok = await launcher.launch();
    if (!ok) return;

    // Poll until Unity's WebSocket server is up (max ~20 s)
    setState(() => _autoConnecting = true);
    _connectRetry?.cancel();
    int attempts = 0;
    _connectRetry = Timer.periodic(const Duration(seconds: 2), (t) async {
      attempts++;
      await conn.connect();           // awaits .ready — safe to check status after
      if (conn.isConnected || attempts >= 10) {
        t.cancel();
        if (!mounted) return;
        setState(() => _autoConnecting = false);
        if (conn.isConnected) Navigator.pushNamed(context, '/monitor');
      }
    });
  }

  Future<void> _pickExe() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe'],
      dialogTitle: 'Select Unity executable',
    );
    if (result != null && result.files.single.path != null) {
      await context.read<UnityLaunchService>().setExePath(result.files.single.path!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final launcher = context.watch<UnityLaunchService>();
    final conn     = context.watch<UnityConnectionService>();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.panelHeader,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(children: [
            const Icon(Icons.sports_esports_outlined, color: AppColors.accent, size: 22),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Unity Exercise Engine', style: GoogleFonts.inter(
                color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600,
              )),
              Text('Launch and control exercises from here',
                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 11)),
            ]),
            const Spacer(),
            _StatusBadge(launcher.status, conn.connectionState),
          ]),
        ),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              // Path picker
              _ExePathRow(
                path: launcher.exePath,
                onPick: _pickExe,
              ),
              const SizedBox(height: 24),

              // Main launch button
              _LaunchButton(
                launcher: launcher,
                conn: conn,
                autoConnecting: _autoConnecting,
                onLaunch: _launchAndConnect,
                onConnect: () {
                  conn.connect();
                  Future.delayed(1.5.seconds, () {
                    if (conn.isConnected && mounted) {
                      Navigator.pushNamed(context, '/monitor');
                    }
                  });
                },
                onStop: launcher.stop,
              ),

              const SizedBox(height: 16),

              // Or connect manually
              _OrDivider(),
              const SizedBox(height: 16),

              Row(children: [
                Expanded(
                  child: _SecondaryBtn(
                    icon: Icons.cable,
                    label: 'Connect to running Unity',
                    subtitle: 'ws://localhost:8765',
                    color: AppColors.accent,
                    onTap: () async {
                      await conn.connect();
                      if (conn.isConnected && mounted) {
                        Navigator.pushNamed(context, '/monitor');
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SecondaryBtn(
                    icon: Icons.play_circle_outline,
                    label: 'Demo mode',
                    subtitle: 'No Unity required',
                    color: AppColors.accentOrange,
                    onTap: () {
                      conn.enableDemoMode();
                      Navigator.pushNamed(context, '/monitor');
                    },
                  ),
                ),
              ]),

              const Spacer(),

              // Error display
              if (launcher.lastError.isNotEmpty)
                _ErrorCard(launcher.lastError),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ExePathRow extends StatelessWidget {
  final String path;
  final VoidCallback onPick;
  const _ExePathRow({required this.path, required this.onPick});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Unity Executable', style: GoogleFonts.inter(
        color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500,
      )),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              path.isEmpty ? 'Not set — click Browse to select' : path,
              style: GoogleFonts.inter(
                color: path.isEmpty ? AppColors.textSecondary : AppColors.textPrimary,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('Browse'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.surfaceLight,
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      Text(
        'Point to your built TeleHealth.exe  •  or the Unity Editor executable',
        style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 9),
      ),
    ],
  );
}

class _LaunchButton extends StatelessWidget {
  final UnityLaunchService launcher;
  final UnityConnectionService conn;
  final bool autoConnecting;
  final VoidCallback onLaunch, onConnect, onStop;
  const _LaunchButton({required this.launcher, required this.conn,
    required this.autoConnecting, required this.onLaunch,
    required this.onConnect, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final launching = launcher.status == UnityProcessStatus.launching || autoConnecting;
    final running   = launcher.status == UnityProcessStatus.running;
    final connected = conn.isConnected;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: launching ? null : (connected ? onConnect : (running ? onConnect : onLaunch)),
        icon: launching
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(connected ? Icons.open_in_new : (running ? Icons.cable : Icons.rocket_launch),
              size: 22),
        label: Text(
          launching     ? 'Launching Unity…'
          : connected   ? 'Open Live Monitor'
          : running     ? 'Connect to Unity'
                        : 'Launch Unity & Connect',
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: connected ? AppColors.accentGreen
                         : running   ? AppColors.accent
                                     : AppColors.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          disabledBackgroundColor: AppColors.accent.withOpacity(0.4),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(children: [
    const Expanded(child: Divider(color: AppColors.border)),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text('or', style: GoogleFonts.inter(
        color: AppColors.textSecondary, fontSize: 11,
      )),
    ),
    const Expanded(child: Divider(color: AppColors.border)),
  ]);
}

class _SecondaryBtn extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _SecondaryBtn({required this.icon, required this.label,
    required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(
            color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500,
          )),
          Text(subtitle, style: GoogleFonts.inter(
            color: AppColors.textSecondary, fontSize: 10,
          )),
        ])),
      ]),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  final UnityProcessStatus process;
  final UnityConnectionStatus connection;
  const _StatusBadge(this.process, this.connection);

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (connection) {
      UnityConnectionStatus.connected    => (AppColors.accentGreen, 'Connected'),
      UnityConnectionStatus.connecting   => (AppColors.accentOrange, 'Connecting…'),
      UnityConnectionStatus.disconnected => switch (process) {
        UnityProcessStatus.running   => (AppColors.accentOrange, 'Unity running'),
        UnityProcessStatus.launching => (AppColors.accentOrange, 'Launching…'),
        _                            => (AppColors.textSecondary, 'Not running'),
      },
      UnityConnectionStatus.error => (AppColors.accentRed, 'Error'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard(this.message);

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.accentRed.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.accentRed.withOpacity(0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline, color: AppColors.accentRed, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: GoogleFonts.inter(
        color: AppColors.accentRed, fontSize: 11,
      ))),
    ]),
  );
}
