import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/pressure_config.dart';
import '../../models/session_models.dart';
import '../../models/telerehab_state.dart';
import '../../services/replay_engine.dart';
import '../../services/session_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/foot_heatmap.dart';
import '../../widgets/skeleton_3d_view.dart';

/// Replay & analysis: browse recorded sessions per patient, play back the
/// 3D skeleton + plantar pressure in sync, and inspect rep-by-rep analytics.
class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  String? _expandedPatient;
  String? _selectedSessionId;
  bool _loadingSession = false;

  /// Cached analytics for the progress view (sessionId → analytics).
  final Map<String, SessionAnalytics> _progressCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionRepository>().refresh();
    });
  }

  Future<void> _openSession(SessionSummary s) async {
    setState(() {
      _loadingSession = true;
      _selectedSessionId = s.sessionId;
    });
    final repo = context.read<SessionRepository>();
    final engine = context.read<ReplayEngine>();
    final loaded = await repo.loadSession(s);
    engine.load(loaded);
    if (mounted) setState(() => _loadingSession = false);
  }

  void _openMock() {
    final engine = context.read<ReplayEngine>();
    engine.load(context.read<SessionRepository>().mockSession());
    setState(() => _selectedSessionId = 'MOCK');
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<ReplayEngine>();

    return Scaffold(
      backgroundColor: AppColors.inkBg,
      body: Column(children: [
        _Header(session: engine.session),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _buildSidebar(),
            const VerticalDivider(width: 1, color: AppColors.inkBorder),
            Expanded(
              child: _loadingSession
                  ? const Center(child: CircularProgressIndicator())
                  : engine.session == null
                      ? _EmptyState(onMock: _openMock)
                      : _PlaybackArea(progressCache: _progressCache),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── session browser ─────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    final repo = context.watch<SessionRepository>();
    return Container(
      width: 268,
      color: const Color(0xFF081224),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Row(children: [
            Text('SESSION LIBRARY',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.inkMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const Spacer(),
            InkWell(
              onTap: repo.refresh,
              child: const Icon(Icons.refresh, size: 14, color: AppColors.inkMuted),
            ),
          ]),
        ),
        Expanded(
          child: repo.patients.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'No recorded sessions found in\n${repo.root}\n\nComplete a live exercise first, or load a mock session below.',
                    style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 10.5),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final p in repo.patients) _patientTile(p, repo),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: OutlinedButton.icon(
            onPressed: _openMock,
            icon: const Icon(Icons.science_outlined, size: 14),
            label: const Text('Load mock session'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentOrange,
              side: BorderSide(color: AppColors.accentOrange.withValues(alpha: 0.4)),
              textStyle: GoogleFonts.schibstedGrotesk(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _patientTile(String patientId, SessionRepository repo) {
    final expanded = _expandedPatient == patientId;
    final sessions = repo.sessionsFor(patientId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () {
          setState(() => _expandedPatient = expanded ? null : patientId);
          if (!expanded) repo.loadSessions(patientId);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: expanded ? AppColors.inkSurfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.person_outline, size: 15, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
                child: Text(patientId,
                    style: GoogleFonts.schibstedGrotesk(
                        color: AppColors.inkText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600))),
            Icon(expanded ? Icons.expand_less : Icons.expand_more,
                size: 16, color: AppColors.inkMuted),
          ]),
        ),
      ),
      if (expanded)
        sessions.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 6),
                child: Text('Loading…',
                    style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 10)),
              )
            : Column(children: [for (final s in sessions) _sessionTile(s)]),
    ]);
  }

  Widget _sessionTile(SessionSummary s) {
    final selected = s.sessionId == _selectedSessionId;
    final when = s.startedAt;
    final classColor = switch (s.exerciseClass) {
      'Idle' => AppColors.inkMuted,
      'MotionCognitive' => const Color(0xFFBB86FC),
      _ => AppColors.accentCyan,
    };
    return InkWell(
      onTap: () => _openSession(s),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(left: 16, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.15) : AppColors.inkSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.inkBorder,
              width: selected ? 1.2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                when != null
                    ? '${when.year}-${_p(when.month)}-${_p(when.day)}  ${_p(when.hour)}:${_p(when.minute)}'
                    : s.sessionId,
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.inkText, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            Text('T${s.manifest.trialNumber}',
                style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 9)),
          ]),
          const SizedBox(height: 3),
          Row(children: [
            _chip(s.classDisplay, classColor),
            const SizedBox(width: 4),
            if (s.manifest.zed.enabled) _chip('ZED', AppColors.accent),
            const SizedBox(width: 4),
            if (s.manifest.fsr.enabled) _chip('FSR', AppColors.accentCyan),
            const SizedBox(width: 4),
            if (s.manifest.eeg.enabled) _chip('EEG', const Color(0xFFBB86FC)),
          ]),
        ]),
      ),
    );
  }

  static String _p(int v) => v.toString().padLeft(2, '0');

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: GoogleFonts.schibstedGrotesk(color: color, fontSize: 8, fontWeight: FontWeight.w600)),
      );
}

// ── header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final RecordedSession? session;
  const _Header({this.session});

  @override
  Widget build(BuildContext context) {
    final m = session?.summary.manifest;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF060F22),
        border: Border(bottom: BorderSide(color: AppColors.inkBorder)),
      ),
      child: Row(children: [
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.inkSurfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.inkBorder),
            ),
            child: const Icon(Icons.arrow_back, color: AppColors.inkText, size: 16),
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.replay_circle_filled_outlined, color: AppColors.accentGreen, size: 18),
        const SizedBox(width: 8),
        Text('Replay & Analysis',
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkText, fontSize: 14, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (m != null) ...[
          Text(
            '${m.patientId}  ·  ${exClassLabel(m.exerciseClass)}  ·  Trial ${m.trialNumber}'
            '${session!.isMock ? '  ·  MOCK DATA' : ''}',
            style: GoogleFonts.schibstedGrotesk(
                color: session!.isMock ? AppColors.accentOrange : AppColors.inkMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w500),
          ),
        ],
        if (session != null && !session!.isMock && session!.summary.folderPath.isNotEmpty) ...[
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _export(context, session!),
            icon: const Icon(Icons.archive_outlined, size: 14),
            label: const Text('Export .zip'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentCyan,
              side: BorderSide(color: AppColors.accentCyan.withValues(alpha: 0.4)),
              textStyle: GoogleFonts.schibstedGrotesk(fontSize: 11, fontWeight: FontWeight.w600),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _export(BuildContext context, RecordedSession s) async {
    final repo = context.read<SessionRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final out = await FilePicker.platform.saveFile(
      dialogTitle: 'Export session bundle',
      fileName: '${s.summary.patientId}_${s.summary.sessionId}.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (out == null) return;
    final path = out.toLowerCase().endsWith('.zip') ? out : '$out.zip';
    messenger.showSnackBar(
        const SnackBar(content: Text('Exporting…'), duration: Duration(seconds: 1)));
    try {
      await repo.exportSessionZip(s.summary.folderPath, path);
      messenger.showSnackBar(SnackBar(content: Text('Exported to $path')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  static String exClassLabel(String token) =>
      token == 'MotionCognitive' ? 'Motion + Cognitive' : token;
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onMock;
  const _EmptyState({required this.onMock});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.replay, size: 56, color: AppColors.inkBorder),
          const SizedBox(height: 12),
          Text('Select a session from the library to replay it',
              style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onMock,
            icon: const Icon(Icons.science_outlined, size: 16),
            label: const Text('Try with a mock session'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentOrange, foregroundColor: Colors.white),
          ),
        ]),
      );
}

// ── playback area ─────────────────────────────────────────────────────────────

class _PlaybackArea extends StatelessWidget {
  final Map<String, SessionAnalytics> progressCache;
  const _PlaybackArea({required this.progressCache});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<ReplayEngine>();
    final skeleton = engine.currentSkeleton();
    final zones = engine.currentZonesNormalised();

    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Left: 3D playback + feet
            Expanded(
              flex: 3,
              child: Column(children: [
                Expanded(
                  flex: 7,
                  child: DashboardPanel(
                    title: '3D Playback',
                    icon: Icons.threed_rotation,
                    child: skeleton == null
                        ? Center(
                            child: Text('No skeleton data in this session',
                                style: GoogleFonts.schibstedGrotesk(
                                    color: AppColors.inkMuted, fontSize: 11)))
                        : Skeleton3DView(skeleton: skeleton),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  flex: 3,
                  child: DashboardPanel(
                    title: 'Plantar Pressure',
                    icon: Icons.accessibility,
                    iconColor: AppColors.accentCyan,
                    child: zones == null
                        ? Center(
                            child: Text('No FSR data in this session',
                                style: GoogleFonts.schibstedGrotesk(
                                    color: AppColors.inkMuted, fontSize: 11)))
                        : Padding(
                            padding: const EdgeInsets.all(6),
                            child: _ReplayFeet(engine: engine, zones: zones),
                          ),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            // Right: analysis tabs
            Expanded(flex: 2, child: _AnalysisTabs(progressCache: progressCache)),
          ]),
        ),
      ),
      if (engine.session?.hasProtocol ?? false) _BlockTimeline(engine: engine),
      _TransportBar(engine: engine),
    ]);
  }
}

/// Renders the recorded foot map(s): one foot for a single-insole (v2) session,
/// two for a legacy two-insole (v1) recording, so both eras stay viewable.
class _ReplayFeet extends StatelessWidget {
  final ReplayEngine engine;
  final (FootZones, FootZones) zones;
  const _ReplayFeet({required this.engine, required this.zones});

  @override
  Widget build(BuildContext context) {
    final session = engine.session;
    if (session != null && session.isSingleFoot) {
      final left = PressureConfig.isLeft(session.foot);
      final z = left ? zones.$1 : zones.$2;
      final label = '${session.foot[0].toUpperCase()}${session.foot.substring(1)} Foot';
      return Center(
        child: FractionallySizedBox(
          widthFactor: 0.5,
          child: FootHeatmap(label: label, zones: z, isLeft: left),
        ),
      );
    }
    return Row(children: [
      Expanded(child: FootHeatmap(label: 'Left', zones: zones.$1, isLeft: true)),
      const SizedBox(width: 8),
      Expanded(child: FootHeatmap(label: 'Right', zones: zones.$2, isLeft: false)),
    ]);
  }
}

// ── block timeline (protocol runs) ──────────────────────────────────────────

class _BlockTimeline extends StatelessWidget {
  final ReplayEngine engine;
  const _BlockTimeline({required this.engine});

  @override
  Widget build(BuildContext context) {
    final s = engine.session!;
    final segs = s.blockSegments;
    final dur = max(1, engine.durationMs);
    final cur = engine.playheadMs;
    final active = s.segmentAt(cur);

    return Container(
      height: 52,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 5),
      decoration: const BoxDecoration(
        color: Color(0xFF060F22),
        border: Border(top: BorderSide(color: AppColors.inkBorder)),
      ),
      child: Column(children: [
        Row(children: [
          Text('BLOCK TIMELINE',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.inkMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(width: 10),
          if (active != null) ...[
            Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: Color(active.colorValue), shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text('Block ${active.blockNumber} · ${active.className}',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.inkText, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ],
          const Spacer(),
          Text('${segs.length} blocks',
              style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 9)),
        ]),
        const SizedBox(height: 5),
        Expanded(
          child: LayoutBuilder(builder: (ctx, cons) {
            final w = cons.maxWidth;
            return Stack(children: [
              Row(children: [
                for (final b in segs)
                  Expanded(
                    flex: (b.endMs - b.startMs).clamp(1, 1 << 30),
                    child: GestureDetector(
                      onTap: () => engine.seekMs(b.startMs),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 0.5),
                        decoration: BoxDecoration(
                          color: Color(b.colorValue).withValues(
                              alpha: active?.blockNumber == b.blockNumber ? 0.95 : 0.45),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        alignment: Alignment.center,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('${b.blockNumber}',
                              style: GoogleFonts.schibstedGrotesk(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
              ]),
              Positioned(
                left: (cur / dur * w).clamp(0.0, w - 2),
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: Colors.white),
              ),
            ]);
          }),
        ),
      ]),
    );
  }
}

// ── transport bar ─────────────────────────────────────────────────────────────

class _TransportBar extends StatelessWidget {
  final ReplayEngine engine;
  const _TransportBar({required this.engine});

  static String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final dur = max(1, engine.durationMs);
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF081224),
        border: Border(top: BorderSide(color: AppColors.inkBorder)),
      ),
      child: Row(children: [
        _btn(Icons.skip_previous, 'Back 1 frame', () => engine.stepFrames(-1)),
        const SizedBox(width: 4),
        InkWell(
          onTap: engine.togglePlay,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent),
            child: Icon(engine.playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white, size: 22),
          ),
        ),
        const SizedBox(width: 4),
        _btn(Icons.stop, 'Stop (rewind to start)', engine.stop),
        const SizedBox(width: 4),
        _btn(Icons.skip_next, 'Forward 1 frame', () => engine.stepFrames(1)),
        const SizedBox(width: 10),
        Text(_fmt(engine.playheadMs),
            style: GoogleFonts.robotoMono(color: AppColors.inkText, fontSize: 11)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.inkBorder,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: engine.playheadMs.clamp(0, dur).toDouble(),
              max: dur.toDouble(),
              onChanged: (v) => engine.seekMs(v.round()),
            ),
          ),
        ),
        Text(_fmt(engine.durationMs),
            style: GoogleFonts.robotoMono(color: AppColors.inkMuted, fontSize: 11)),
        const SizedBox(width: 12),
        for (final s in const [0.25, 0.5, 1.0, 2.0, 4.0])
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: InkWell(
              onTap: () => engine.setSpeed(s),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: engine.speed == s ? AppColors.accent : AppColors.inkSurfaceAlt,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                      color: engine.speed == s ? AppColors.accent : AppColors.inkBorder),
                ),
                child: Text('${s}x',
                    style: GoogleFonts.schibstedGrotesk(
                        color: engine.speed == s ? Colors.white : AppColors.inkMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _btn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.inkSurfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.inkBorder),
            ),
            child: Icon(icon, size: 16, color: AppColors.inkText),
          ),
        ),
      );
}

// ── analysis tabs ─────────────────────────────────────────────────────────────

class _AnalysisTabs extends StatefulWidget {
  final Map<String, SessionAnalytics> progressCache;
  const _AnalysisTabs({required this.progressCache});

  @override
  State<_AnalysisTabs> createState() => _AnalysisTabsState();
}

class _AnalysisTabsState extends State<_AnalysisTabs> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<ReplayEngine>();
    final a = engine.analytics;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.inkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inkBorder),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            color: AppColors.inkSurfaceAlt,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            for (final (i, label, icon) in const [
              (0, 'Charts', Icons.show_chart),
              (1, 'Reps', Icons.repeat),
              (2, 'Summary', Icons.assessment_outlined),
            ])
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _tab = i),
                  borderRadius: BorderRadius.circular(7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: _tab == i ? AppColors.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icon,
                          size: 13, color: _tab == i ? Colors.white : AppColors.inkMuted),
                      const SizedBox(width: 5),
                      Text(label,
                          style: GoogleFonts.schibstedGrotesk(
                              color: _tab == i ? Colors.white : AppColors.inkMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(
          child: switch (_tab) {
            0 => _ChartsTab(engine: engine),
            1 => _RepsTab(analytics: a),
            _ => _SummaryTab(engine: engine, progressCache: widget.progressCache),
          },
        ),
      ]),
    );
  }
}

// Downsample a series to at most [maxPts] points for chart performance.
List<FlSpot> _spots(List<(int, double)> series, {int maxPts = 400}) {
  if (series.isEmpty) return const [];
  final step = max(1, series.length ~/ maxPts);
  return [
    for (var i = 0; i < series.length; i += step)
      FlSpot(series[i].$1 / 1000.0, series[i].$2),
  ];
}

class _ChartsTab extends StatelessWidget {
  final ReplayEngine engine;
  const _ChartsTab({required this.engine});

  @override
  Widget build(BuildContext context) {
    final a = engine.analytics;
    final playheadSec = engine.playheadMs / 1000.0;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        Expanded(
            child: _chart(
          context,
          title: 'Knee angle (${a.activeSide == 'L' ? 'left' : 'right'}) — deg',
          lines: [(_spots(a.angleSeries), AppColors.accentGreen)],
          playheadSec: playheadSec,
          reps: a.reps,
        )),
        const SizedBox(height: 8),
        Expanded(
            child: _chart(
          context,
          title: a.asymmetrySeries.isEmpty
              ? 'Total load (%)'
              : 'Total load (%) & L−R asymmetry (%)',
          lines: [
            (_spots(a.loadSeries), AppColors.accentCyan),
            if (a.asymmetrySeries.isNotEmpty)
              (_spots(a.asymmetrySeries), AppColors.accentOrange),
          ],
          playheadSec: playheadSec,
        )),
      ]),
    );
  }

  Widget _chart(
    BuildContext context, {
    required String title,
    required List<(List<FlSpot>, Color)> lines,
    required double playheadSec,
    List<RepInfo> reps = const [],
  }) {
    final hasData = lines.any((l) => l.$1.length > 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 9.5)),
      const SizedBox(height: 4),
      Expanded(
        child: !hasData
            ? Center(
                child: Text('No data',
                    style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 10)))
            : LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppColors.inkBorder, strokeWidth: 0.5),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                            style: GoogleFonts.schibstedGrotesk(
                                color: AppColors.inkMuted, fontSize: 8)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 16,
                        getTitlesWidget: (v, _) => Text('${v.toInt()}s',
                            style: GoogleFonts.schibstedGrotesk(
                                color: AppColors.inkMuted, fontSize: 8)),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                      show: true, border: Border(bottom: BorderSide(color: AppColors.inkBorder))),
                  lineTouchData: LineTouchData(
                    touchCallback: (event, response) {
                      final x = response?.lineBarSpots?.firstOrNull?.x;
                      if (x != null && event is FlTapUpEvent) {
                        engine.seekMs((x * 1000).round());
                      }
                    },
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem(
                              '${s.y.toStringAsFixed(1)} @ ${s.x.toStringAsFixed(1)}s',
                              GoogleFonts.schibstedGrotesk(color: Colors.white, fontSize: 9)))
                          .toList(),
                    ),
                  ),
                  rangeAnnotations: RangeAnnotations(verticalRangeAnnotations: [
                    for (final r in reps)
                      VerticalRangeAnnotation(
                        x1: r.startMs / 1000.0,
                        x2: r.endMs / 1000.0,
                        color: AppColors.accentGreen.withValues(alpha: 0.06),
                      ),
                  ]),
                  extraLinesData: ExtraLinesData(verticalLines: [
                    VerticalLine(
                      x: playheadSec,
                      color: Colors.white.withValues(alpha: 0.7),
                      strokeWidth: 1,
                      dashArray: [4, 3],
                    ),
                  ]),
                  lineBarsData: [
                    for (final (spots, color) in lines)
                      LineChartBarData(
                        spots: spots,
                        isCurved: false,
                        color: color,
                        barWidth: 1.6,
                        dotData: const FlDotData(show: false),
                        belowBarData:
                            BarAreaData(show: true, color: color.withValues(alpha: 0.05)),
                      ),
                  ],
                ),
              ),
      ),
    ]);
  }
}

class _RepsTab extends StatelessWidget {
  final SessionAnalytics analytics;
  const _RepsTab({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final reps = analytics.reps;
    if (reps.isEmpty) {
      return Center(
          child: Text('No repetitions detected',
              style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 11)));
    }
    final engine = context.read<ReplayEngine>();
    final maxRom = reps.map((r) => r.rom).reduce(max);

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        // ROM per rep bars
        SizedBox(
          height: 110,
          child: BarChart(
            BarChartData(
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) => Text('${v.toInt() + 1}',
                        style:
                            GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 8)),
                  ),
                ),
              ),
              barGroups: [
                for (final r in reps)
                  BarChartGroupData(x: r.index - 1, barRods: [
                    BarChartRodData(
                      toY: r.rom,
                      width: 10,
                      borderRadius: BorderRadius.circular(2),
                      color: r.rom > maxRom * 0.8
                          ? AppColors.accentGreen
                          : AppColors.accentOrange,
                    ),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          _h('Rep', 30),
          _h('Start', 44),
          _h('ROM', 44),
          _h('Time', 44),
          _h('Smooth', 50),
          const Spacer(),
        ]),
        const Divider(color: AppColors.inkBorder, height: 8),
        Expanded(
          child: ListView(children: [
            for (final r in reps)
              InkWell(
                onTap: () => engine.seekMs(r.startMs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    _c('${r.index}', 30, bold: true),
                    _c('${(r.startMs / 1000).toStringAsFixed(1)}s', 44),
                    _c('${r.rom.toStringAsFixed(0)}°', 44,
                        color: r.rom > maxRom * 0.8
                            ? AppColors.accentGreen
                            : AppColors.accentOrange),
                    _c('${r.durationSec.toStringAsFixed(1)}s', 44),
                    _c('${(r.smoothness * 100).toStringAsFixed(0)}%', 50),
                    const Spacer(),
                    const Icon(Icons.play_arrow, size: 12, color: AppColors.inkMuted),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _h(String s, double w) => SizedBox(
      width: w,
      child: Text(s,
          style: GoogleFonts.schibstedGrotesk(
              color: AppColors.inkMuted, fontSize: 9, fontWeight: FontWeight.w600)));

  Widget _c(String s, double w, {bool bold = false, Color? color}) => SizedBox(
      width: w,
      child: Text(s,
          style: GoogleFonts.schibstedGrotesk(
              color: color ?? AppColors.inkText,
              fontSize: 10,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400)));
}

class _SummaryTab extends StatelessWidget {
  final ReplayEngine engine;
  final Map<String, SessionAnalytics> progressCache;
  const _SummaryTab({required this.engine, required this.progressCache});

  @override
  Widget build(BuildContext context) {
    final a = engine.analytics;
    final s = engine.session!;
    final dur = s.summary.manifest.duration;

    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('SESSION REPORT',
          style: GoogleFonts.schibstedGrotesk(
              color: AppColors.inkMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _metric('Repetitions', '${a.reps.length}', AppColors.accent),
        _metric('Mean ROM', '${a.meanRom.toStringAsFixed(0)}°', AppColors.accentGreen),
        _metric('Best ROM', '${a.bestRom.toStringAsFixed(0)}°', AppColors.accentGreen),
        _metric('Mean rep time', '${a.meanRepDuration.toStringAsFixed(1)}s', AppColors.accentCyan),
        if (a.asymmetrySeries.isNotEmpty)
          _metric('Asymmetry', '${a.meanAsymmetry.toStringAsFixed(1)}%',
              a.meanAsymmetry < 15 ? AppColors.accentGreen : AppColors.accentOrange),
        _metric('Smoothness', '${(a.meanSmoothness * 100).toStringAsFixed(0)}%',
            a.meanSmoothness > 0.6 ? AppColors.accentGreen : AppColors.accentOrange),
        _metric(
            'Duration',
            dur != null
                ? '${dur.inMinutes}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}'
                : '${(s.durationMs / 1000).toStringAsFixed(0)}s',
            AppColors.inkMuted),
        _metric('Frames', '${s.frames.length}', AppColors.inkMuted),
        if (s.hasEeg)
          _metric('EEG samples', '${s.eeg.length}', const Color(0xFFBB86FC)),
      ]),
      const SizedBox(height: 16),
      Text('PROGRESS ACROSS SESSIONS',
          style: GoogleFonts.schibstedGrotesk(
              color: AppColors.inkMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5)),
      const SizedBox(height: 8),
      _ProgressView(current: s, progressCache: progressCache),
    ]);
  }

  Widget _metric(String label, String value, Color color) => Container(
        width: 106,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.inkSurfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.inkBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 9)),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.schibstedGrotesk(color: color, fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Lazily computes mean-ROM and rep count for every other session of the same
/// patient + class, so the clinician sees trial-over-trial improvement.
class _ProgressView extends StatefulWidget {
  final RecordedSession current;
  final Map<String, SessionAnalytics> progressCache;
  const _ProgressView({required this.current, required this.progressCache});

  @override
  State<_ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<_ProgressView> {
  List<(SessionSummary, SessionAnalytics)>? _rows;
  bool _loading = false;

  Future<void> _compute() async {
    setState(() => _loading = true);
    final repo = context.read<SessionRepository>();
    final cur = widget.current.summary;
    final sessions = await repo.loadSessions(cur.patientId);
    final sameClass = sessions
        .where((s) => s.exerciseClass == cur.manifest.exerciseClass)
        .toList()
      ..sort((a, b) =>
          (a.startedAt ?? DateTime(0)).compareTo(b.startedAt ?? DateTime(0)));

    final rows = <(SessionSummary, SessionAnalytics)>[];
    for (final s in sameClass) {
      var a = widget.progressCache[s.sessionId];
      if (a == null) {
        if (s.sessionId == cur.sessionId) {
          a = ReplayEngine.analyse(widget.current);
        } else {
          a = ReplayEngine.analyse(await repo.loadSession(s));
        }
        widget.progressCache[s.sessionId] = a;
      }
      rows.add((s, a));
    }
    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.current.isMock) {
      return Text('Progress view is unavailable for mock sessions.',
          style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 10.5));
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final rows = _rows;
    if (rows == null) {
      return OutlinedButton.icon(
        onPressed: _compute,
        icon: const Icon(Icons.trending_up, size: 14),
        label: const Text('Compute progress for this patient'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
          textStyle: GoogleFonts.schibstedGrotesk(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
    }
    if (rows.length < 2) {
      return Text('Only one session of this class recorded so far — record more to see trends.',
          style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 10.5));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 110,
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(
                show: true, border: Border(bottom: BorderSide(color: AppColors.inkBorder))),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                      style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 8)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) => Text('T${v.toInt() + 1}',
                      style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 8)),
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < rows.length; i++) FlSpot(i.toDouble(), rows[i].$2.meanRom),
                ],
                color: AppColors.accentGreen,
                barWidth: 2,
                isCurved: false,
                dotData: const FlDotData(show: true),
              ),
              LineChartBarData(
                spots: [
                  for (var i = 0; i < rows.length; i++)
                    FlSpot(i.toDouble(), rows[i].$2.reps.length.toDouble()),
                ],
                color: AppColors.accent,
                barWidth: 2,
                isCurved: false,
                dotData: const FlDotData(show: true),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 4),
      Row(children: [
        _legend(AppColors.accentGreen, 'Mean ROM (°)'),
        const SizedBox(width: 10),
        _legend(AppColors.accent, 'Reps'),
      ]),
    ]);
  }

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 3, color: c),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 9)),
      ]);
}
