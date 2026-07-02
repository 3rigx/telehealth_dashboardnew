import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/protocol.dart';
import '../../models/skeleton_3d.dart';
import '../../models/telerehab_state.dart';
import '../../services/protocol_run_controller.dart';
import '../../services/protocol_runner.dart';
import '../../services/signal_quality.dart';
import '../../services/unity_connection_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eeg_channel_map.dart';
import '../../widgets/foot_heatmap.dart';
import '../../widgets/sensor_warmup_loader.dart';
import '../../widgets/skeleton_3d_view.dart';

/// Full-screen, distraction-light participant view. Driven by a
/// [ProtocolRunner] (the Flutter clock) and the live sensor stream. This is the
/// "single-window toggle" participant mode — pushed as a route over the
/// dashboard. Phase 2 runs it as a rehearsal (no Unity recording yet).
class ParticipantScreen extends StatefulWidget {
  final Protocol protocol;
  final int? seed;

  /// When provided, this is a LIVE run: the controller drives the Unity
  /// recording lifecycle and owns the runner. When null, it's a local rehearsal.
  final ProtocolRunController? controller;

  const ParticipantScreen({
    super.key,
    required this.protocol,
    this.seed,
    this.controller,
  });

  @override
  State<ParticipantScreen> createState() => _ParticipantScreenState();
}

class _ParticipantScreenState extends State<ParticipantScreen> {
  ProtocolRunner? _ownRunner; // rehearsal only (no controller)
  UnityConnectionService? _conn;

  // Operator can hide the pressure / EEG feedback panels mid-run.
  bool _hidePressure = false;
  bool _hideEeg = false;

  ProtocolRunController? get _ctrl => widget.controller;
  ProtocolRunner get _runner => _ctrl?.runner ?? _ownRunner!;

  @override
  void initState() {
    super.initState();
    _conn = context.read<UnityConnectionService>()..addListener(_onSensor);
    final c = _ctrl;
    if (c == null) {
      _ownRunner = ProtocolRunner()..addListener(_onChange);
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _ownRunner!.start(widget.protocol, seed: widget.seed));
    } else {
      c.addListener(_onChange);
      c.runner.addListener(_onChange);
      WidgetsBinding.instance.addPostFrameCallback((_) => c.prepare());
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onSensor() {
    _runner.feedSensor(_conn!.state);
    if (mounted) setState(() {});
  }

  void _exit() {
    final c = _ctrl;
    if (c != null && c.stage == RunStage.recording) {
      c.abort(); // finish → save; the Done screen offers Finish
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _conn?.removeListener(_onSensor);
    final c = _ctrl;
    if (c == null) {
      _ownRunner!
        ..removeListener(_onChange)
        ..dispose();
    } else {
      c.removeListener(_onChange);
      c.runner.removeListener(_onChange);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cls = _runner.currentClass;
    final accent = cls?.color ?? AppColors.accent;
    final state = _conn?.state ?? TelerehabState.demo;

    return Scaffold(
      backgroundColor: const Color(0xFF05080F),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.4),
            radius: 1.3,
            colors: [accent.withValues(alpha: 0.16), const Color(0xFF05080F)],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            _controlStrip(accent),
            Expanded(child: _content(state, cls, accent)),
          ]),
        ),
      ),
    );
  }

  // ── researcher control strip ──────────────────────────────────────────────

  Widget _controlStrip(Color accent) {
    final running = _runner.isRunning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.inkBorder)),
      ),
      child: Row(children: [
        Text(widget.protocol.title,
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkText, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 14),
        if (_runner.totalBlocks > 0)
          Text('Block ${_runner.blockNumber} / ${_runner.totalBlocks}',
              style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 12)),
        const SizedBox(width: 12),
        _phaseChip(accent),
        const SizedBox(width: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _runner.overallProgress,
              minHeight: 5,
              backgroundColor: AppColors.inkSurfaceAlt,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ),
        const SizedBox(width: 16),
        if (running) ...[
          _ctrlToggle(Icons.directions_walk, _hidePressure ? 'Show pressure' : 'Hide pressure',
              !_hidePressure, () => setState(() => _hidePressure = !_hidePressure)),
          const SizedBox(width: 8),
          _ctrlToggle(Icons.psychology_outlined, _hideEeg ? 'Show EEG' : 'Hide EEG',
              !_hideEeg, () => setState(() => _hideEeg = !_hideEeg)),
          const SizedBox(width: 8),
          _ctrlBtn(_runner.isPaused ? Icons.play_arrow : Icons.pause,
              _runner.isPaused ? 'Resume' : 'Pause', _runner.togglePause),
          const SizedBox(width: 8),
          _ctrlBtn(Icons.skip_next, 'Skip block', _runner.skipBlock),
          const SizedBox(width: 8),
        ],
        _ctrlBtn(Icons.close, 'Exit', _exit),
      ]),
    );
  }

  Widget _phaseChip(Color accent) {
    final p = _runner.phase;
    final color = switch (p) {
      RunPhase.active => AppColors.accentGreen,
      RunPhase.pause => AppColors.accentOrange,
      RunPhase.done => AppColors.accentCyan,
      _ => accent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(p.label.toUpperCase(),
          style: GoogleFonts.schibstedGrotesk(
              color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    );
  }

  Widget _ctrlBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.inkSurfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.inkBorder),
            ),
            child: Icon(icon, size: 16, color: AppColors.inkText),
          ),
        ),
      );

  /// Control-strip toggle that dims when its panel is hidden.
  Widget _ctrlToggle(IconData icon, String tip, bool on, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: on ? AppColors.accent.withValues(alpha: 0.18) : AppColors.inkSurfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: on ? AppColors.accent.withValues(alpha: 0.6) : AppColors.inkBorder),
            ),
            child: Icon(icon, size: 16, color: on ? AppColors.accent : AppColors.inkMuted),
          ),
        ),
      );

  // ── content: live-stage overlays vs the phase body ─────────────────────

  Widget _content(TelerehabState state, ProtocolClass? cls, Color accent) {
    final c = _ctrl;
    if (c == null) return _body(state, cls, accent); // rehearsal
    switch (c.stage) {
      case RunStage.recording:
        return _runner.isDone
            ? _stageOverlay(null, 'Saving session…')
            : _body(state, cls, accent);
      case RunStage.done:
        return _doneView();
      case RunStage.ready:
        return _beginOverlay(c, accent);
      case RunStage.saving:
        return _stageOverlay(null, c.message.isEmpty ? 'Saving session…' : c.message);
      case RunStage.error:
        return _errorOverlay(c.message);
      case RunStage.idle:
      case RunStage.connecting:
      case RunStage.preparing:
        final title = c.stage == RunStage.connecting
            ? 'Connecting…'
            : c.stage == RunStage.preparing
                ? 'Warming up sensors'
                : 'Preparing…';
        return SensorWarmupLoader(
            title: title, message: c.message.isEmpty ? null : c.message);
    }
  }

  Widget _beginOverlay(ProtocolRunController c, Color accent) {
    final report = c.signalReport;
    final gated = report.hasChecks && !report.allOk;
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.play_circle_fill, size: 76, color: accent),
        const SizedBox(height: 18),
        Text(widget.protocol.title,
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkText, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(c.message,
              textAlign: TextAlign.center,
              style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 14)),
        ),
        if (report.hasChecks) ...[
          const SizedBox(height: 20),
          _signalChecklist(report),
        ],
        if (gated) ...[
          const SizedBox(height: 10),
          _overrideToggle(c),
        ],
        const SizedBox(height: 22),
        ElevatedButton.icon(
          onPressed: c.canBegin ? c.begin : null,
          icon: const Icon(Icons.fiber_manual_record, size: 16),
          label: Text(gated && c.canBegin ? 'Begin anyway' : 'Begin recording'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentGreen,
            foregroundColor: Colors.black,
            disabledBackgroundColor: Colors.white10,
            disabledForegroundColor: AppColors.inkMuted,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            textStyle: GoogleFonts.schibstedGrotesk(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        Text(
            '${widget.protocol.normalizedBlockCount} blocks · ~${_fmt(widget.protocol.estimatedDuration)} · recording is continuous',
            style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 11)),
      ]),
    );
  }

  /// Pre-flight signal check — one row per enabled sensor, refreshed live.
  Widget _signalChecklist(SignalReport report) => Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final s in report.sensors) _signalRow(s)],
        ),
      );

  Widget _signalRow(SensorSignal s) {
    final (color, icon) = switch (s.level) {
      SignalLevel.ok => (AppColors.accentGreen, Icons.check_circle),
      SignalLevel.warn => (AppColors.accentOrange, Icons.error_outline),
      SignalLevel.bad => (AppColors.accentRed, Icons.highlight_off),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(s.label,
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkText, fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        Flexible(
          child: Text(s.detail,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.schibstedGrotesk(color: color, fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _overrideToggle(ProtocolRunController c) => TextButton.icon(
        onPressed: () => c.setOverrideGate(!c.overrideQualityGate),
        icon: Icon(
            c.overrideQualityGate
                ? Icons.check_box
                : Icons.check_box_outline_blank,
            size: 18,
            color: c.overrideQualityGate ? AppColors.accentOrange : AppColors.inkMuted),
        label: Text('Start anyway — I’ve checked the sensors',
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkMuted, fontSize: 12)),
      );

  Widget _stageOverlay(IconData? icon, String msg) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon == null)
            const SizedBox(
                width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3))
          else
            Icon(icon, size: 48, color: AppColors.inkMuted),
          const SizedBox(height: 18),
          Text(msg,
              textAlign: TextAlign.center,
              style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 15)),
        ]),
      );

  Widget _errorOverlay(String msg) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 60, color: AppColors.accentRed),
          const SizedBox(height: 16),
          Text('Could not start the run',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.inkText, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(msg,
                textAlign: TextAlign.center,
                style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 14)),
          ),
          const SizedBox(height: 22),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Back'),
          ),
        ]),
      );

  // ── body per phase ──────────────────────────────────────────────────────

  Widget _body(TelerehabState state, ProtocolClass? cls, Color accent) {
    switch (_runner.phase) {
      case RunPhase.done:
        return _doneView();
      case RunPhase.pause:
        return _pauseView();
      case RunPhase.instruction:
        return _instructionView(cls, accent);
      case RunPhase.reset:
        return _resetView();
      case RunPhase.active:
        return _activeView(state, cls, accent);
      case RunPhase.idle:
        return const Center(child: CircularProgressIndicator());
    }
  }

  Widget _instructionView(ProtocolClass? cls, Color accent) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('GET READY',
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkMuted, fontSize: 14, letterSpacing: 3)),
        const SizedBox(height: 12),
        Text(cls?.name ?? '',
            style: GoogleFonts.schibstedGrotesk(
                color: accent, fontSize: 56, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        if ((cls?.instruction ?? '').isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(cls!.instruction,
                textAlign: TextAlign.center,
                style: GoogleFonts.schibstedGrotesk(color: AppColors.inkText, fontSize: 20)),
          ),
        if (cls != null && cls.cognitivePrompt) ...[
          const SizedBox(height: 10),
          _hintPill(Icons.record_voice_over, 'Count out loud'),
        ],
        if (cls != null && cls.animationPath.isNotEmpty) ...[
          const SizedBox(height: 22),
          _refAnimation(cls),
        ],
        const SizedBox(height: 28),
        _countdown(accent),
      ]),
    );
  }

  Widget _resetView() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.replay, size: 48, color: AppColors.accentCyan.withValues(alpha: 0.8)),
        const SizedBox(height: 16),
        Text('RESET',
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.accentCyan, fontSize: 40, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Return to start position',
            style: GoogleFonts.schibstedGrotesk(color: AppColors.inkText, fontSize: 18)),
        const SizedBox(height: 26),
        _countdown(AppColors.accentCyan),
      ]),
    );
  }

  Widget _pauseView() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.pause_circle_outline, size: 64, color: AppColors.accentOrange),
        const SizedBox(height: 16),
        Text('Paused',
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkText, fontSize: 34, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Take a moment. Resume when the participant is ready.',
            style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 15)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _runner.resume,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Resume'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentGreen,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            textStyle: GoogleFonts.schibstedGrotesk(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  Widget _doneView() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.check_circle_outline, size: 72, color: AppColors.accentGreen),
        const SizedBox(height: 16),
        Text('Protocol complete',
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkText, fontSize: 32, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _stat('${_runner.totalBlocks}', 'blocks'),
          const SizedBox(width: 28),
          _stat('${_runner.totalReps}', 'total reps'),
          const SizedBox(width: 28),
          _stat(_fmt(widget.protocol.estimatedDuration), 'planned'),
        ]),
        if (_ctrl?.savedFolder != null) ...[
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.folder_open, size: 15, color: AppColors.accentGreen),
              const SizedBox(width: 8),
              Flexible(
                child: Text(_ctrl!.savedFolder!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 11)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.done),
          label: const Text('Finish'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            textStyle: GoogleFonts.schibstedGrotesk(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  // ── active view + feedback ────────────────────────────────────────────────

  Widget _activeView(TelerehabState state, ProtocolClass? cls, Color accent) {
    final g = widget.protocol.globalFeedback;
    final fb = cls?.feedback ?? ClassFeedback();
    final showRep = g && fb.repCounter;
    final showMirror = g && fb.movementMirror;
    final showPressure = g && fb.pressureIndicator && !_hidePressure;
    final showEeg = g && fb.eegFeedback && !_hideEeg;

    final hasGuide = (cls?.animationPath ?? '').isNotEmpty;

    // Large panels: the looping exercise-guide GIF and the live movement mirror.
    final primary = <Widget>[
      if (hasGuide) _panel('Exercise guide', _guidePlayer(cls!)),
      if (showMirror) _panel('Movement Mirror', _mirror(state)),
    ];
    // Compact side cards.
    final side = <Widget>[
      if (showRep) _repCard(accent),
      if (showPressure) _pressureCard(state),
      if (showEeg) _eegCard(state),
    ];

    Widget content;
    if (primary.isNotEmpty) {
      final primaryArea = primary.length == 1
          ? primary.first
          : Row(children: [
              for (var i = 0; i < primary.length; i++) ...[
                Expanded(child: primary[i]),
                if (i != primary.length - 1) const SizedBox(width: 14),
              ],
            ]);
      content = Row(children: [
        Expanded(flex: 3, child: primaryArea),
        if (side.isNotEmpty) ...[
          const SizedBox(width: 14),
          SizedBox(width: 340, child: _stack(side)),
        ],
      ]);
    } else if (side.isEmpty) {
      content = _calmCenter(cls, accent);
    } else {
      content = Row(children: [
        for (var i = 0; i < side.length; i++) ...[
          Expanded(child: side[i]),
          if (i != side.length - 1) const SizedBox(width: 14),
        ],
      ]);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _activeHeader(cls, accent),
        const SizedBox(height: 14),
        Expanded(child: content),
      ]),
    );
  }

  Widget _activeHeader(ProtocolClass? cls, Color accent) {
    final remain = _runner.phaseRemaining.ceil();
    final total = (cls?.activeSec ?? widget.protocol.activeSec).round();
    return Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Text(cls?.name ?? '',
          style: GoogleFonts.schibstedGrotesk(
              color: AppColors.inkText, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(width: 14),
      if ((cls?.instruction ?? '').isNotEmpty)
        Expanded(
          child: Text(cls!.instruction,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 14)),
        )
      else
        const Spacer(),
      const SizedBox(width: 14),
      Text('$remain s',
          style: GoogleFonts.schibstedGrotesk(
              color: accent, fontSize: 20, fontWeight: FontWeight.w700)),
      Text(' / $total s',
          style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 13)),
      const SizedBox(width: 12),
      SizedBox(
        width: 220,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _runner.phaseProgress,
            minHeight: 6,
            backgroundColor: AppColors.inkSurfaceAlt,
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
      ),
    ]);
  }

  Widget _stack(List<Widget> panels) => Column(children: [
        for (var i = 0; i < panels.length; i++) ...[
          Expanded(child: panels[i]),
          if (i != panels.length - 1) const SizedBox(height: 14),
        ],
      ]);

  Widget _mirror(TelerehabState state) =>
      Skeleton3DView(skeleton: state.skeleton ?? Skeleton3D.seatedDemo(kneeAngleDeg: 50));

  Widget _repCard(Color accent) =>
      _panel('Repetitions', Center(child: _RepGauge(reps: _runner.reps, accent: accent)));

  Widget _pressureCard(TelerehabState state) {
    final p = state.plantar;
    final lSum = p.left.sum, rSum = p.right.sum;
    final total = lSum + rSum;
    final leftPct = total <= 0 ? 0.5 : lSum / total;
    return _panel(
      'Pressure Balance',
      Column(children: [
        Expanded(
          child: Row(children: [
            Expanded(child: FootHeatmap(label: 'LEFT', zones: p.left, isLeft: true)),
            const SizedBox(width: 8),
            Expanded(child: FootHeatmap(label: 'RIGHT', zones: p.right, isLeft: false)),
          ]),
        ),
        const SizedBox(height: 8),
        _balanceBar(leftPct.toDouble()),
      ]),
    );
  }

  Widget _balanceBar(double leftPct) {
    final rightPct = 1 - leftPct;
    final balanced = (leftPct - 0.5).abs() < 0.08;
    final color = balanced ? AppColors.accentGreen : AppColors.accentOrange;
    return Column(children: [
      Row(children: [
        Text('L ${(leftPct * 100).round()}%',
            style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 11)),
        const Spacer(),
        Text('${(rightPct * 100).round()}% R',
            style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 11)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(children: [
          Expanded(
            flex: (leftPct * 1000).round().clamp(1, 1000),
            child: Container(height: 8, color: color.withValues(alpha: 0.85)),
          ),
          Container(width: 2, height: 8, color: Colors.white),
          Expanded(
            flex: (rightPct * 1000).round().clamp(1, 1000),
            child: Container(height: 8, color: color.withValues(alpha: 0.55)),
          ),
        ]),
      ),
    ]);
  }

  Widget _eegCard(TelerehabState state) =>
      _panel('Brain Activity', EegChannelMap(channels: state.eeg?.channels ?? const []));

  Widget _calmCenter(ProtocolClass? cls, Color accent) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.self_improvement, size: 64, color: accent.withValues(alpha: 0.8)),
          const SizedBox(height: 16),
          Text(cls?.name ?? '',
              style: GoogleFonts.schibstedGrotesk(
                  color: accent, fontSize: 40, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if ((cls?.instruction ?? '').isNotEmpty)
            Text(cls!.instruction,
                style: GoogleFonts.schibstedGrotesk(color: AppColors.inkText, fontSize: 18)),
        ]),
      );

  // ── small bits ──────────────────────────────────────────────────────────

  Widget _panel(String title, Widget child) => Container(
        decoration: BoxDecoration(
          color: AppColors.inkSurface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.inkBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(title.toUpperCase(),
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.inkMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4)),
          ),
          Expanded(child: Padding(padding: const EdgeInsets.all(8), child: child)),
        ]),
      );

  Widget _countdown(Color color) {
    final remain = _runner.phaseRemaining.ceil();
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: 120,
          height: 120,
          child: CircularProgressIndicator(
            value: (1 - _runner.phaseProgress).clamp(0.0, 1.0),
            strokeWidth: 7,
            backgroundColor: AppColors.inkSurfaceAlt,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        Text('$remain',
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkText, fontSize: 42, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _hintPill(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.accentOrange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: AppColors.accentOrange),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.accentOrange, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _stat(String value, String label) => Column(children: [
        Text(value,
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkText, fontSize: 30, fontWeight: FontWeight.w800)),
        Text(label, style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 12)),
      ]);

  /// The looping exercise-guide animation that fills its panel during the
  /// active block (GIF / animated WebP render; video formats show a placeholder
  /// until the video_player package is added).
  Widget _guidePlayer(ProtocolClass c) {
    final ext = c.animationPath.split('.').last.toLowerCase();
    if (ext == 'gif' || ext == 'webp') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(c.animationPath),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, e, s) => _animPlaceholder(c),
        ),
      );
    }
    return _animPlaceholder(c);
  }

  Widget _refAnimation(ProtocolClass c) {
    final ext = c.animationPath.split('.').last.toLowerCase();
    if (ext == 'gif' || ext == 'webp') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(c.animationPath),
          height: 180,
          fit: BoxFit.contain,
          errorBuilder: (_, e, s) => _animPlaceholder(c),
        ),
      );
    }
    return _animPlaceholder(c);
  }

  Widget _animPlaceholder(ProtocolClass c) => Container(
        height: 120,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.inkSurfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.inkBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.movie_outlined, size: 22, color: AppColors.inkMuted),
          const SizedBox(width: 10),
          Flexible(
            child: Text(c.animationPath.split(RegExp(r'[\\/]')).last,
                style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 12)),
          ),
        ]),
      );

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

/// Gamified rep counter: a progress ring that fills every [_milestone] reps
/// (a "level"), a number that pops on each rep, a flame streak for completed
/// sets, and an escalating cheer at each milestone.
class _RepGauge extends StatefulWidget {
  final int reps;
  final Color accent;
  const _RepGauge({required this.reps, required this.accent});

  @override
  State<_RepGauge> createState() => _RepGaugeState();
}

class _RepGaugeState extends State<_RepGauge> with SingleTickerProviderStateMixin {
  static const _milestone = 5;
  late final AnimationController _pop;
  String _cheer = '';

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  }

  @override
  void didUpdateWidget(covariant _RepGauge old) {
    super.didUpdateWidget(old);
    if (widget.reps > old.reps) {
      _pop.forward(from: 0); // pop on each new rep
      _cheer = (widget.reps % _milestone == 0) ? _cheerFor(widget.reps) : '';
    } else if (widget.reps < old.reps) {
      _cheer = ''; // reps reset → new block
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  static String _cheerFor(int n) => switch (n) {
        5 => 'Nice! 🔥',
        10 => 'Great! 🔥🔥',
        15 => 'On fire! 🔥🔥🔥',
        20 => 'Unstoppable!',
        _ => '$n in a row!',
      };

  @override
  Widget build(BuildContext context) {
    final reps = widget.reps;
    final completed = reps ~/ _milestone;
    final within = reps % _milestone;
    final ring = reps == 0 ? 0.0 : (within == 0 ? 1.0 : within / _milestone);

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 170,
        height: 170,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 170,
            height: 170,
            child: CircularProgressIndicator(
              value: ring,
              strokeWidth: 11,
              backgroundColor: AppColors.inkSurfaceAlt,
              valueColor: AlwaysStoppedAnimation(widget.accent),
            ),
          ),
          AnimatedBuilder(
            animation: _pop,
            builder: (context, _) {
              final scale = 1 + 0.3 * (1 - Curves.easeOut.transform(_pop.value));
              return Transform.scale(
                scale: scale,
                child: Text('$reps',
                    style: GoogleFonts.schibstedGrotesk(
                        color: AppColors.inkText,
                        fontSize: 68,
                        fontWeight: FontWeight.w800,
                        height: 1)),
              );
            },
          ),
        ]),
      ),
      const SizedBox(height: 10),
      if (completed > 0)
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < (completed > 6 ? 6 : completed); i++)
            const Icon(Icons.local_fire_department, size: 18, color: AppColors.accentOrange),
          if (completed > 6)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text('×$completed',
                  style: GoogleFonts.schibstedGrotesk(
                      color: AppColors.accentOrange, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
      const SizedBox(height: 4),
      Text(_cheer.isNotEmpty ? _cheer : 'reps this block',
          style: GoogleFonts.schibstedGrotesk(
              color: _cheer.isNotEmpty ? widget.accent : AppColors.inkMuted,
              fontSize: 13,
              fontWeight: _cheer.isNotEmpty ? FontWeight.w700 : FontWeight.w400)),
    ]);
  }
}
