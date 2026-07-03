import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/app_settings.dart';
import '../../services/session_repository.dart';
import '../../services/unity_connection_service.dart';
import '../../services/unity_launch_service.dart';
import '../../theme/app_theme.dart';

/// Landing screen: pick what to do (Live Exercise / Replay / Prediction),
/// then — for live modes — configure the session (patient, class, sensors)
/// and launch/attach to Unity.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// null = mode cards; 'Exercise' | 'Prediction' = session setup panel.
  String? _setupMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UnityLaunchService>().init();
      context.read<SessionRepository>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.isDark
                ? [const Color(0xFF1B1B1B), AppColors.background, const Color(0xFF141414)]
                : [const Color(0xFFFFEFE0), AppColors.background, const Color(0xFFF3ECFB)],
          ),
        ),
        child: SafeArea(
          child: Row(children: [
            _LeftRail(
              onExercise: () => setState(() => _setupMode = 'Exercise'),
              onReplay: () => Navigator.pushNamed(context, '/replay'),
              onPrediction: () => setState(() => _setupMode = 'Prediction'),
              onProtocols: () => Navigator.pushNamed(context, '/protocols'),
              onExercises: () => Navigator.pushNamed(context, '/exercises'),
              onSettings: () => Navigator.pushNamed(context, '/settings'),
              activeMode: _setupMode,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _setupMode == null
                    ? const _WelcomePanel()
                    : SessionSetupPanel(
                        mode: _setupMode!,
                        onBack: () => setState(() => _setupMode = null),
                      ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── left rail ─────────────────────────────────────────────────────────────────

class _LeftRail extends StatelessWidget {
  final VoidCallback onExercise, onReplay, onPrediction, onProtocols,
      onExercises, onSettings;
  final String? activeMode;
  const _LeftRail({
    required this.onExercise,
    required this.onReplay,
    required this.onPrediction,
    required this.onProtocols,
    required this.onExercises,
    required this.onSettings,
    this.activeMode,
  });

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<UnityConnectionService>();
    final launcher = context.watch<UnityLaunchService>();
    final settings = context.watch<AppSettings>();

    return SizedBox(
      width: 312,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.accessibility_new, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Text('TeleRehab',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              tooltip: settings.darkMode ? 'Switch to light mode' : 'Switch to dark mode',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  context.read<AppSettings>().setDarkMode(!settings.darkMode),
              icon: Icon(
                settings.darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
          ]).animate().fadeIn().slideY(begin: -0.2),
          const SizedBox(height: 8),
          Text('capture · replay · analyse',
              style: AppTheme.eyebrow(size: 19, color: AppColors.muted))
              .animate()
              .fadeIn(delay: 150.ms),
          const SizedBox(height: 36),
          _NavCard(
            icon: Icons.monitor_heart_outlined,
            title: 'Live Exercise',
            subtitle: 'Run a capture session with\npatient, sensors & class',
            color: AppColors.accent,
            active: activeMode == 'Exercise',
            onTap: onExercise,
            delay: 0,
          ),
          const SizedBox(height: 10),
          _NavCard(
            icon: Icons.replay_circle_filled_outlined,
            title: 'Replay',
            subtitle: 'Review & analyse a\ncompleted session',
            color: AppColors.accentGreen,
            onTap: onReplay,
            delay: 80,
          ),
          const SizedBox(height: 10),
          _NavCard(
            icon: Icons.psychology_outlined,
            title: 'Prediction',
            subtitle: 'Live model inference\n(experimental)',
            color: const Color(0xFFBB86FC),
            active: activeMode == 'Prediction',
            onTap: onPrediction,
            delay: 160,
          ),
          const SizedBox(height: 10),
          _NavCard(
            icon: Icons.science_outlined,
            title: 'Protocol Builder',
            subtitle: 'Design research protocols,\nblocks & timing',
            color: AppColors.accentCyan,
            onTap: onProtocols,
            delay: 200,
          ),
          const SizedBox(height: 10),
          _NavCard(
            icon: Icons.directions_run_outlined,
            title: 'Exercises',
            subtitle: 'Record & manage exercise\nguides (avatar)',
            color: const Color(0xFFD98AB0),
            onTap: onExercises,
            delay: 240,
          ),
          const SizedBox(height: 10),
          _NavCard(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'FSR port, sensors,\nmock data, folders',
            color: const Color(0xFF8A9BB5),
            onTap: onSettings,
            delay: 240,
          ),
          const Spacer(),
          _StatusLine(
            label: 'Unity',
            color: conn.isConnected
                ? AppColors.accentGreen
                : launcher.isRunning
                    ? AppColors.accentOrange
                    : AppColors.textSecondary,
            text: conn.isConnected
                ? 'Connected'
                : launcher.isRunning
                    ? 'Running, not connected'
                    : 'Not running',
          ),
          if (conn.anyMock)
            const _StatusLine(
                label: 'Mock', color: AppColors.accentOrange, text: 'Mock data active'),
          const SizedBox(height: 8),
          Text('v2.0.0 • Research Use Only',
              style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 10)),
        ]),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final String label;
  final Color color;
  final String text;
  const _StatusLine({required this.label, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Container(
              width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 6),
          Text('$label: ', style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 10)),
          Text(text,
              style: GoogleFonts.schibstedGrotesk(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _NavCard extends StatefulWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  final int delay;
  final bool active;
  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    required this.delay,
    this.active = false,
  });
  @override
  State<_NavCard> createState() => _NavCardState();
}

class _NavCardState extends State<_NavCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: 150.ms,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: _hovered || widget.active
                  ? widget.color.withValues(alpha: 0.12)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: _hovered || widget.active
                    ? widget.color.withValues(alpha: 0.6)
                    : AppColors.border,
                width: _hovered || widget.active ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(widget.icon, color: widget.color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title,
                      style: GoogleFonts.schibstedGrotesk(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                  Text(widget.subtitle,
                      style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 10)),
                ]),
              ),
              Icon(Icons.chevron_right, color: widget.color.withValues(alpha: 0.6), size: 16),
            ]),
          ),
        ),
      ).animate().fadeIn(delay: Duration(milliseconds: widget.delay + 250)).slideX(begin: -0.1);
}

// ── welcome panel (no mode selected) ──────────────────────────────────────────

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final repo = context.watch<SessionRepository>();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('welcome —', style: AppTheme.eyebrow(size: 22)),
        Text('Capture, replay, analyse',
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.textPrimary, fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'Choose a mode on the left to begin. Live Exercise launches and drives the Unity engine; Replay works entirely from recorded files.',
          style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 28),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _fact(Icons.people_outline, '${repo.patients.length}', 'patients on record'),
          _fact(Icons.sensors, settings.fsrConnType, 'FSR connection'),
          if (settings.fsrConnType == 'USB')
            _fact(Icons.usb, settings.fsrUsbPort.isEmpty ? 'not set' : settings.fsrUsbPort,
                'FSR serial port'),
          _fact(Icons.psychology_outlined, settings.eegEnabled ? 'On' : 'Off', 'EEG headset'),
          if (settings.anyMock)
            _fact(Icons.science_outlined,
                [
                  if (settings.mockMotion) 'Motion',
                  if (settings.mockFsr) 'FSR',
                  if (settings.mockEeg) 'EEG',
                ].join(' · '),
                'mocked sensors'),
        ]),
        const Spacer(),
        Text(
          'Tip — enable mock data in Settings to explore every screen without hardware or Unity.',
          style: GoogleFonts.schibstedGrotesk(
              color: AppColors.textSecondary.withValues(alpha: 0.7), fontSize: 11),
        ),
      ]),
    ).animate().fadeIn();
  }

  Widget _fact(IconData icon, String value, String label) => Container(
        width: 170,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.lavender,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: AppColors.violet),
          const SizedBox(height: 8),
          Text(value,
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
          Text(label, style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 10)),
        ]),
      );
}

// ── session setup panel ───────────────────────────────────────────────────────

class SessionSetupPanel extends StatefulWidget {
  final String mode; // Exercise | Prediction
  final VoidCallback onBack;
  const SessionSetupPanel({super.key, required this.mode, required this.onBack});

  @override
  State<SessionSetupPanel> createState() => _SessionSetupPanelState();
}

class _SessionSetupPanelState extends State<SessionSetupPanel> {
  late final TextEditingController _patientCtrl;
  String _exerciseClass = 'Motion';
  String _status = '';
  bool _busy = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _patientCtrl =
        TextEditingController(text: context.read<AppSettings>().lastPatientId);
    // Pre-load trial numbers for the picked patient.
    final repo = context.read<SessionRepository>();
    if (_patientCtrl.text.isNotEmpty) repo.loadSessions(_patientCtrl.text);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _patientCtrl.dispose();
    super.dispose();
  }

  String get _patientId => _patientCtrl.text.trim();

  Future<void> _start({required bool mockOnly}) async {
    if (_patientId.isEmpty) {
      setState(() => _status = 'Enter or pick a patient ID first.');
      return;
    }
    final settings = context.read<AppSettings>();
    final conn = context.read<UnityConnectionService>();
    final launcher = context.read<UnityLaunchService>();
    settings.setLastPatientId(_patientId);

    if (mockOnly) {
      conn.setMocks(motion: true, fsr: true, eeg: true);
      settings.setAllMock(true);
      if (mounted) Navigator.pushNamed(context, '/monitor');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Preparing Unity…';
    });

    // Apply the per-sensor mock choices from Settings.
    conn.setMocks(
        motion: settings.mockMotion, fsr: settings.mockFsr, eeg: settings.mockEeg);

    // 1. make sure the process is up. Try attaching to an already-running
    // Unity first (editor in Play mode, or a manually started build) so we
    // never spawn a second instance that would fight over the port.
    if (!conn.isConnected && !launcher.isRunning) {
      setState(() => _status = 'Looking for a running Unity…');
      await conn.connect(settings.wsUri);
    }
    if (!conn.isConnected && !launcher.isRunning) {
      setState(() => _status = 'Launching Unity…');
      final ok = await launcher.launch();
      if (!ok) {
        setState(() {
          _busy = false;
          _status = launcher.lastError.isEmpty
              ? 'Could not launch Unity — set the executable path in Settings, '
                'or press Play in the Unity editor first.'
              : launcher.lastError;
        });
        return;
      }
    }

    // 2. connect (poll up to ~24 s while the engine boots)
    if (!conn.isConnected) {
      setState(() => _status = 'Connecting to Unity…');
      var attempts = 0;
      final completer = Completer<bool>();
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
        attempts++;
        await conn.connect(settings.wsUri);
        if (conn.isConnected || attempts >= 12) {
          t.cancel();
          if (!completer.isCompleted) completer.complete(conn.isConnected);
        }
      });
      final connected = await completer.future;
      if (!mounted) return;
      if (!connected) {
        setState(() {
          _busy = false;
          _status = 'Unity did not answer on ${settings.wsUri}. Is the build up to date?';
        });
        return;
      }
    }

    // 3. push configuration, then start
    setState(() => _status = 'Configuring session…');
    conn.configureSession(settings.toUnityConfig(
      patientId: _patientId,
      exerciseClass: _exerciseClass,
      mode: widget.mode,
    ));
    await Future.delayed(const Duration(milliseconds: 400));
    conn.startSession();

    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '';
    });
    Navigator.pushNamed(context, '/monitor');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final repo = context.watch<SessionRepository>();
    final isPrediction = widget.mode == 'Prediction';
    final trial = _patientId.isEmpty ? null : repo.nextTrialNumber(_patientId, _exerciseClass);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.panelHeader,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.panel)),
          ),
          child: Row(children: [
            Icon(isPrediction ? Icons.psychology_outlined : Icons.monitor_heart_outlined,
                color: isPrediction ? const Color(0xFFBB86FC) : AppColors.accent, size: 20),
            const SizedBox(width: 10),
            Text('${isPrediction ? 'Prediction' : 'Exercise'} — Session Setup',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (trial != null)
              Text('Trial #$trial',
                  style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11)),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            // ── patient ────────────────────────────────────────────────────
            _sectionLabel('PATIENT'),
            const SizedBox(height: 8),
            TextField(
              controller: _patientCtrl,
              onChanged: (v) {
                setState(() {});
                if (v.trim().isNotEmpty) repo.loadSessions(v.trim());
              },
              style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Type a new patient ID, or pick an existing one below',
                hintStyle: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 12),
                prefixIcon:
                    const Icon(Icons.person_outline, size: 18, color: AppColors.accent),
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
            if (repo.patients.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in repo.patients)
                  InkWell(
                    onTap: () {
                      _patientCtrl.text = p;
                      repo.loadSessions(p);
                      setState(() {});
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _patientId == p
                            ? AppColors.accent.withValues(alpha: 0.2)
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _patientId == p ? AppColors.accent : AppColors.border),
                      ),
                      child: Text(p,
                          style: GoogleFonts.schibstedGrotesk(
                              color: _patientId == p
                                  ? AppColors.accent
                                  : AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ]),
            ],
            const SizedBox(height: 22),

            // ── exercise class ─────────────────────────────────────────────
            if (!isPrediction) ...[
              _sectionLabel('EXERCISE CLASS'),
              const SizedBox(height: 8),
              Row(children: [
                for (final c in kExerciseClasses) ...[
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _exerciseClass = c),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _exerciseClass == c
                              ? AppColors.accent
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  _exerciseClass == c ? AppColors.accent : AppColors.border),
                        ),
                        child: Text(exerciseClassDisplay(c),
                            style: GoogleFonts.schibstedGrotesk(
                                color: _exerciseClass == c
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  if (c != kExerciseClasses.last) const SizedBox(width: 10),
                ],
              ]),
              const SizedBox(height: 22),
            ],

            // ── sensors ────────────────────────────────────────────────────
            _sectionLabel('SENSORS'),
            const SizedBox(height: 8),
            Row(children: [
              _sensorPill('ZED', settings.zedEnabled, settings.setZedEnabled,
                  mocked: settings.mockMotion),
              const SizedBox(width: 10),
              _sensorPill('FSR', settings.fsrEnabled, settings.setFsrEnabled,
                  mocked: settings.mockFsr),
              const SizedBox(width: 10),
              _sensorPill('EEG', settings.eegEnabled, settings.setEegEnabled,
                  mocked: settings.mockEeg),
            ]),
            const SizedBox(height: 10),
            // FSR connection summary with jump to settings
            InkWell(
              onTap: () => Navigator.pushNamed(context, '/settings'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  const Icon(Icons.cable, size: 14, color: AppColors.accentCyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'FSR via ${settings.fsrConnType}'
                      '${settings.fsrConnType == 'USB' ? '  ·  ${settings.fsrUsbPort.isEmpty ? "port not set" : settings.fsrUsbPort}' : ''}'
                      '${(settings.fsrConnType == 'WebSocket' || settings.fsrConnType == 'TCP') ? '  ·  ${settings.fsrUri.isEmpty ? "host not set" : settings.fsrUri}' : ''}',
                      style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 11),
                    ),
                  ),
                  Text('Change in Settings',
                      style: GoogleFonts.schibstedGrotesk(color: AppColors.accent, fontSize: 10)),
                  const Icon(Icons.chevron_right, size: 14, color: AppColors.accent),
                ]),
              ),
            ),
            const SizedBox(height: 22),

            // ── unity exe quick set (only when missing) ────────────────────
            _UnityPathHint(),
          ]),
        ),

        // ── footer: status + actions ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [
            TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Back'),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_status,
                  style: GoogleFonts.schibstedGrotesk(
                      color: _status.contains('…')
                          ? AppColors.textSecondary
                          : AppColors.accentRed,
                      fontSize: 11)),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _start(mockOnly: true),
              icon: const Icon(Icons.science_outlined, size: 15),
              label: const Text('Start with mock data'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentOrange,
                side: BorderSide(color: AppColors.accentOrange.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: const StadiumBorder(),
                textStyle: GoogleFonts.schibstedGrotesk(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _busy ? null : () => _start(mockOnly: false),
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.rocket_launch, size: 15),
              label: Text(_busy ? 'Starting…' : 'Launch & Start Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: const StadiumBorder(),
                elevation: 0,
                textStyle: GoogleFonts.schibstedGrotesk(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
      ]),
    ).animate().fadeIn().slideX(begin: 0.04);
  }

  Widget _sectionLabel(String s) => Text(s,
      style: GoogleFonts.schibstedGrotesk(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5));

  Widget _sensorPill(String label, bool on, ValueChanged<bool> set, {bool mocked = false}) =>
      Expanded(
        child: InkWell(
          onTap: () => set(!on),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: on ? AppColors.accent.withValues(alpha: 0.18) : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? AppColors.accent : AppColors.border),
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(on ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 14, color: on ? AppColors.accentGreen : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(label,
                    style: GoogleFonts.schibstedGrotesk(
                        color: on ? AppColors.textPrimary : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ]),
              if (mocked)
                Text('MOCK',
                    style: GoogleFonts.schibstedGrotesk(
                        color: AppColors.accentOrange,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
            ]),
          ),
        ),
      );
}

/// Inline warning + picker shown only while the Unity exe path is unset.
class _UnityPathHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final launcher = context.watch<UnityLaunchService>();
    if (launcher.exePath.isNotEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_outlined, size: 16, color: AppColors.accentOrange),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Unity executable not set — needed for live capture (mock mode works without it).',
            style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 11),
          ),
        ),
        TextButton(
          onPressed: () async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['exe'],
              dialogTitle: 'Select Unity executable',
            );
            final path = result?.files.single.path;
            if (path != null && context.mounted) {
              context.read<UnityLaunchService>().setExePath(path);
            }
          },
          child: Text('Browse…',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.accentOrange, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
