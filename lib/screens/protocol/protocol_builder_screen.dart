import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/exercise_asset.dart';
import '../../models/protocol.dart';
import '../../services/app_settings.dart';
import '../../services/exercise_repository.dart';
import '../../services/protocol_repository.dart';
import '../../services/protocol_run_controller.dart';
import '../../services/unity_connection_service.dart';
import '../../services/unity_launch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/participant_picker.dart';
import 'participant_screen.dart';

/// Protocol Builder — design a research protocol (classes, block sequence,
/// timing, per-class feedback), save as a draft, and publish. Phase 1: pure
/// Flutter authoring + JSON persistence; the runtime/participant screen and
/// Unity markers come in later phases.
class ProtocolBuilderScreen extends StatefulWidget {
  const ProtocolBuilderScreen({super.key});

  @override
  State<ProtocolBuilderScreen> createState() => _ProtocolBuilderScreenState();
}

class _ProtocolBuilderScreenState extends State<ProtocolBuilderScreen> {
  Protocol? _draft; // working copy (cloned from the stored protocol)
  bool _dirty = false;
  int _previewSeed = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<ProtocolRepository>().refresh());
  }

  // ── working-copy lifecycle ──────────────────────────────────────────────

  void _edit(VoidCallback fn) => setState(() {
        fn();
        _dirty = true;
      });

  void _open(Protocol p) => setState(() {
        _draft = p.clone();
        _dirty = false;
        _previewSeed++;
      });

  void _new({required bool template}) => setState(() {
        _draft = template ? Protocol.template() : Protocol.blank();
        _dirty = true;
        _previewSeed++;
      });

  Future<void> _save() async {
    final p = _draft;
    if (p == null) return;
    if (p.title.trim().isEmpty) p.title = 'Untitled Protocol';
    await context.read<ProtocolRepository>().save(p);
    if (!mounted) return;
    setState(() => _dirty = false);
    _toast('Saved “${p.title}”');
  }

  Future<void> _publish() async {
    final p = _draft;
    if (p == null) return;
    if (p.classes.isEmpty) {
      _toast('Add at least one class before publishing.');
      return;
    }
    await context.read<ProtocolRepository>().publish(p);
    if (!mounted) return;
    setState(() => _dirty = false);
    _toast('Published “${p.title}” (v${p.version})');
  }

  void _rehearse() {
    final p = _draft;
    if (p == null) return;
    if (p.classes.isEmpty) {
      _toast('Add at least one class first.');
      return;
    }
    // Clone so edits after launching don't mutate the running copy.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ParticipantScreen(protocol: p.clone())),
    );
  }

  /// Live run: prompts for a participant ID, then drives Unity to record one
  /// continuous session with block/phase markers written into the saved folder.
  Future<void> _runLive() async {
    final p = _draft;
    if (p == null) return;
    if (p.classes.isEmpty) {
      _toast('Add at least one class first.');
      return;
    }
    final settings = context.read<AppSettings>();
    final conn = context.read<UnityConnectionService>();
    final launcher = context.read<UnityLaunchService>();
    // Strict pseudonymity: participant must be picked from the enrolled
    // registry — free-text IDs can no longer reach folder names / run.json.
    final id = await pickParticipant(context, initial: settings.lastPatientId);
    if (id == null || id.trim().isEmpty) return;
    settings.setLastPatientId(id.trim());

    final controller = ProtocolRunController(
      conn: conn,
      settings: settings,
      protocol: p.clone(),
      participantId: id.trim(),
      launcher: launcher,
    );
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ParticipantScreen(protocol: controller.protocol, controller: controller),
    ));
  }

  Future<void> _delete(Protocol p) async {
    final repo = context.read<ProtocolRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete protocol?',
            style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary)),
        content: Text('“${p.title}” will be permanently removed.',
            style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repo.delete(p.id);
    if (mounted && _draft?.id == p.id) setState(() => _draft = null);
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.schibstedGrotesk(fontSize: 12)),
          backgroundColor: AppColors.surfaceLight,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );

  // ── build ───────────────────────────────────────────────────────────────

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
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _buildLibrary(),
            Expanded(
              child: _draft == null
                  ? const _EmptyEditor()
                  : KeyedSubtree(key: ValueKey(_draft!.id), child: _buildEditor()),
            ),
          ]),
        ),
      ),
    );
  }

  // ── left: protocol library ──────────────────────────────────────────────

  Widget _buildLibrary() {
    final repo = context.watch<ProtocolRepository>();
    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Row(children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back, size: 18, color: AppColors.textSecondary),
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 2),
            Icon(Icons.science_outlined, size: 20, color: AppColors.accent),
            const SizedBox(width: 8),
            Text('Protocols',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${repo.protocols.length}',
                style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 12)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _new(template: false),
                icon: const Icon(Icons.add, size: 15),
                label: const Text('New'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
                  textStyle: GoogleFonts.schibstedGrotesk(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _new(template: true),
                icon: const Icon(Icons.auto_awesome, size: 15),
                label: const Text('Template'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentGreen,
                  side: BorderSide(color: AppColors.accentGreen.withValues(alpha: 0.4)),
                  textStyle: GoogleFonts.schibstedGrotesk(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: repo.protocols.isEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No protocols yet.\nStart from the template, or create a new one.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  itemCount: repo.protocols.length,
                  itemBuilder: (_, i) {
                    final p = repo.protocols[i];
                    return _LibraryTile(
                      protocol: p,
                      selected: _draft?.id == p.id,
                      onTap: () => _open(p),
                      onDelete: () => _delete(p),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  // ── right: editor ───────────────────────────────────────────────────────

  Widget _buildEditor() {
    final p = _draft!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // header
      Container(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('design a study —', style: AppTheme.eyebrow(size: 18)),
            Row(children: [
              Text('Protocol Builder',
                  style: GoogleFonts.schibstedGrotesk(
                      color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              if (p.published)
                _badge('PUBLISHED v${p.version}', AppColors.accentGreen)
              else
                _badge('DRAFT', AppColors.textSecondary),
              if (_dirty) ...[
                const SizedBox(width: 8),
                _badge('UNSAVED', AppColors.accentOrange),
              ],
            ]),
            const SizedBox(height: 2),
            Text('Configure your classes, blocks, and timing',
                style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 12)),
          ]),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _rehearse,
            icon: const Icon(Icons.play_circle_outline, size: 15),
            label: const Text('Rehearse'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentGreen,
              side: BorderSide(color: AppColors.accentGreen.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: GoogleFonts.schibstedGrotesk(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _runLive,
            icon: const Icon(Icons.fiber_manual_record, size: 14),
            label: const Text('Run Live'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: GoogleFonts.schibstedGrotesk(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined, size: 15),
            label: const Text('Save Draft'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: GoogleFonts.schibstedGrotesk(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _publish,
            icon: const Icon(Icons.send, size: 15),
            label: const Text('Publish Protocol'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              textStyle: GoogleFonts.schibstedGrotesk(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
          children: [
            _configCard(p),
            const SizedBox(height: 16),
            _classEditor(p),
            const SizedBox(height: 16),
            _sequenceCard(p),
          ],
        ).animate().fadeIn(duration: 200.ms),
      ),
    ]);
  }

  // ── config card ─────────────────────────────────────────────────────────

  Widget _configCard(Protocol p) {
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('STUDY'),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: p.title,
          onChanged: (v) => _edit(() => p.title = v),
          style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 14),
          decoration: _inputDecoration('Study title'),
        ),
        const SizedBox(height: 18),
        Wrap(spacing: 28, runSpacing: 18, crossAxisAlignment: WrapCrossAlignment.start, children: [
          _stepper(
            label: 'Classes',
            value: p.classes.length,
            onMinus: p.classes.length > 1 ? () => _edit(() => p.classes.removeLast()) : null,
            onPlus: () => _edit(() => _addClass(p)),
          ),
          _stepper(
            label: 'Blocks',
            value: p.blockCount,
            hint: p.blockCountRounded ? 'runs ${p.normalizedBlockCount} (even split)' : null,
            onMinus:
                p.blockCount > p.classes.length ? () => _edit(() => p.blockCount--) : null,
            onPlus: () => _edit(() => p.blockCount++),
          ),
          _miniToggle(
            label: 'Global Feedback',
            value: p.globalFeedback,
            onChanged: (v) => _edit(() => p.globalFeedback = v),
          ),
        ]),
        const SizedBox(height: 18),
        _sectionLabel('BLOCK ORDER'),
        const SizedBox(height: 8),
        Row(children: [
          for (final m in BlockOrderMode.values) ...[
            _orderChip(p, m),
            if (m != BlockOrderMode.values.last) const SizedBox(width: 10),
          ],
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            const Icon(Icons.schedule, size: 16, color: AppColors.accentCyan),
            const SizedBox(width: 8),
            Text('Estimated run: ',
                style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 12)),
            Text(_fmtDur(p.estimatedDuration),
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
            Expanded(
              child: Text(
                  '  ·  ${p.normalizedBlockCount} blocks · timing set per class below · + comfort pauses',
                  style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        _sectionLabel('SENSORS ENABLED'),
        const SizedBox(height: 8),
        Row(children: [
          _sensorPill('Motion Tracking', 'ZED Camera', p.sensorZed,
              (v) => _edit(() => p.sensorZed = v)),
          const SizedBox(width: 10),
          _sensorPill('Plantar Pressure', 'Foot Insoles', p.sensorFsr,
              (v) => _edit(() => p.sensorFsr = v)),
          const SizedBox(width: 10),
          _sensorPill('EEG', 'EEG Headset', p.sensorEeg, (v) => _edit(() => p.sensorEeg = v)),
        ]),
      ]),
    );
  }

  void _addClass(Protocol p) {
    final color = kClassPalette[p.classes.length % kClassPalette.length];
    p.classes.add(ProtocolClass(
      id: genId('c'),
      name: 'Class ${p.classes.length + 1}',
      colorValue: color,
      baseToken: 'Motion',
      // Seed timing from the protocol defaults; editable per class below.
      instructionSec: p.instructionSec,
      activeSec: p.activeSec,
      resetSec: p.resetSec,
    ));
  }

  // ── class editor ────────────────────────────────────────────────────────

  Widget _classEditor(Protocol p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _sectionLabel('CLASS EDITOR'),
        const SizedBox(width: 8),
        Text('(${p.classes.length})',
            style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11)),
        const Spacer(),
        TextButton.icon(
          onPressed: () => _edit(() => _addClass(p)),
          icon: const Icon(Icons.add, size: 15),
          label: const Text('Add Class'),
          style: TextButton.styleFrom(foregroundColor: AppColors.accent),
        ),
      ]),
      const SizedBox(height: 8),
      Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (var i = 0; i < p.classes.length; i++)
            _ClassCard(
              key: ValueKey(p.classes[i].id),
              cls: p.classes[i],
              index: i,
              globalFeedback: p.globalFeedback,
              onEdit: _edit,
              onDelete:
                  p.classes.length > 1 ? () => _edit(() => p.classes.removeAt(i)) : null,
            ),
        ],
      ),
    ]);
  }

  // ── sequence preview ────────────────────────────────────────────────────

  Widget _sequenceCard(Protocol p) {
    final seq = p.generateSequence(seed: _previewSeed);
    final reorderable = p.orderMode != BlockOrderMode.fixed;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionLabel('BLOCK SEQUENCE'),
          const SizedBox(width: 8),
          Text('(${seq.length} blocks · ${p.orderMode.token})',
              style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11)),
          const Spacer(),
          if (reorderable)
            TextButton.icon(
              onPressed: () => setState(() => _previewSeed++),
              icon: const Icon(Icons.casino_outlined, size: 15),
              label: const Text('Reshuffle preview'),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            ),
        ]),
        const SizedBox(height: 4),
        Text(p.orderMode.blurb,
            style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 12),
        if (seq.isEmpty)
          Text('Add classes to generate a sequence.',
              style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 12))
        else
          Wrap(spacing: 6, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (var i = 0; i < seq.length; i++) ...[
              _blockChip(i + 1, p.classById(seq[i])),
              if (i != seq.length - 1) _resetChip(p.resetSec),
            ],
          ]),
        const SizedBox(height: 14),
        Wrap(spacing: 16, runSpacing: 8, children: [
          for (final c in p.classes) _legendDot(c.color, '${c.name}  ×${p.blocksPerClass}'),
          _legendDot(AppColors.textSecondary, 'R = reset (per class)'),
        ]),
        const SizedBox(height: 8),
        Text(
          reorderable
              ? 'Preview only — the real order is generated per run, with the seed stored for reproducibility.'
              : 'Fixed round-robin order, identical every run.',
          style: GoogleFonts.schibstedGrotesk(
              color: AppColors.textSecondary.withValues(alpha: 0.7), fontSize: 10.5),
        ),
      ]),
    );
  }

  // ── small builders ──────────────────────────────────────────────────────

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(text,
            style: GoogleFonts.schibstedGrotesk(
                color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      );

  Widget _sectionLabel(String s) => Text(s,
      style: GoogleFonts.schibstedGrotesk(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5));

  Widget _stepper({
    required String label,
    required int value,
    String? hint,
    VoidCallback? onMinus,
    VoidCallback? onPlus,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _stepBtn(Icons.remove, onMinus),
          Container(
            width: 46,
            alignment: Alignment.center,
            child: Text('$value',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          _stepBtn(Icons.add, onPlus),
        ]),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint, style: GoogleFonts.schibstedGrotesk(color: AppColors.accentOrange, fontSize: 10)),
        ],
      ]);

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: onTap == null ? AppColors.surface : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon,
              size: 16,
              color: onTap == null ? AppColors.textSecondary.withValues(alpha: 0.4) : AppColors.textPrimary),
        ),
      );

  Widget _miniToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.accent,
          ),
          Text(value ? 'Enabled' : 'Disabled',
              style: GoogleFonts.schibstedGrotesk(
                  color: value ? AppColors.textPrimary : AppColors.textSecondary, fontSize: 12)),
        ]),
      ]);

  Widget _orderChip(Protocol p, BlockOrderMode mode) {
    final on = p.orderMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => _edit(() => p.orderMode = mode),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: on ? AppColors.accent.withValues(alpha: 0.18) : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? AppColors.accent : AppColors.border),
          ),
          child: Row(children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 15, color: on ? AppColors.accent : AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(mode.token,
                style: GoogleFonts.schibstedGrotesk(
                    color: on ? AppColors.textPrimary : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _sensorPill(String title, String sub, bool on, ValueChanged<bool> onChanged) => Expanded(
        child: InkWell(
          onTap: () => onChanged(!on),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: on ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? AppColors.accent : AppColors.border),
            ),
            child: Row(children: [
              Icon(on ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16, color: on ? AppColors.accentGreen : AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: GoogleFonts.schibstedGrotesk(
                          color: on ? AppColors.textPrimary : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  Text(sub,
                      style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 9.5),
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        ),
      );

  Widget _blockChip(int n, ProtocolClass? c) {
    final color = c?.color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$n', style: GoogleFonts.schibstedGrotesk(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
        Text(c?.name ?? '?',
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _resetChip(double sec) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Text('R',
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _legendDot(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11)),
      ]);

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.accent)),
      );

  static String _fmtDur(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

// ── library tile ────────────────────────────────────────────────────────────

class _LibraryTile extends StatelessWidget {
  final Protocol protocol;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _LibraryTile({
    required this.protocol,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = protocol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceLight : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.accent.withValues(alpha: 0.6) : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.schibstedGrotesk(
                        color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: (p.published ? AppColors.accentGreen : AppColors.textSecondary)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(p.published ? 'Published v${p.version}' : 'Draft',
                        style: GoogleFonts.schibstedGrotesk(
                            color: p.published ? AppColors.accentGreen : AppColors.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Text('${p.classes.length} cls · ${p.normalizedBlockCount} blk',
                      style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 10)),
                ]),
              ]),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 16),
              color: AppColors.textSecondary,
              visualDensity: VisualDensity.compact,
              tooltip: 'Delete',
            ),
          ]),
        ),
      ),
    );
  }
}

// ── empty editor ────────────────────────────────────────────────────────────

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.science_outlined,
              size: 56, color: AppColors.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('Select a protocol, or create a new one',
              style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 4),
          Text('“Template” gives you the REST / MOVE / MOVE+COUNT seated study.',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.textSecondary.withValues(alpha: 0.7), fontSize: 11)),
        ]),
      );
}

// ── class card ──────────────────────────────────────────────────────────────

class _ClassCard extends StatelessWidget {
  final ProtocolClass cls;
  final int index;
  final bool globalFeedback;
  final void Function(VoidCallback) onEdit;
  final VoidCallback? onDelete;

  const _ClassCard({
    super.key,
    required this.cls,
    required this.index,
    required this.globalFeedback,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cls.color.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // header: index, name, delete
        Row(children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cls.color, borderRadius: BorderRadius.circular(6)),
            child: Text('${index + 1}',
                style: GoogleFonts.schibstedGrotesk(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: cls.name,
              onChanged: (v) => onEdit(() => cls.name = v),
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Class name',
              ),
            ),
          ),
          if (onDelete != null)
            InkWell(
              onTap: onDelete,
              child: Icon(Icons.close, size: 16, color: AppColors.textSecondary),
            ),
        ]),
        Divider(color: AppColors.border, height: 18),

        // base token
        _miniLabel('CAPTURE TYPE'),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: kBaseTokens.contains(cls.baseToken) ? cls.baseToken : kBaseTokens.first,
              isDense: true,
              isExpanded: true,
              dropdownColor: AppColors.surfaceLight,
              style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 12),
              items: [
                for (final t in kBaseTokens)
                  DropdownMenuItem(value: t, child: Text(baseTokenDisplay(t))),
              ],
              onChanged: (v) => onEdit(() => cls.baseToken = v ?? cls.baseToken),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // exercise type
        _miniLabel('EXERCISE TYPE'),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: cls.exerciseType,
          onChanged: (v) => onEdit(() => cls.exerciseType = v),
          style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 12),
          decoration: _dec('e.g. Seated Leg Extensions'),
        ),
        const SizedBox(height: 10),

        // exercise guide (authored avatar) — the block's reference movement
        _miniLabel('EXERCISE GUIDE (AVATAR)'),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(
              cls.exerciseId.isEmpty
                  ? 'None'
                  : (cls.exerciseType.isEmpty ? 'Selected' : cls.exerciseType),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.schibstedGrotesk(
                  color: cls.exerciseId.isEmpty
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontSize: 11),
            ),
          ),
          if (cls.exerciseId.isNotEmpty)
            InkWell(
              onTap: () => onEdit(() => cls.exerciseId = ''),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.clear, size: 14, color: AppColors.textSecondary),
              ),
            ),
          TextButton.icon(
            onPressed: () => _pickExercise(context, cls, onEdit),
            icon: const Icon(Icons.directions_run, size: 14),
            label: const Text('Choose'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: GoogleFonts.schibstedGrotesk(fontSize: 11),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        // instruction
        _miniLabel('INSTRUCTION'),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: cls.instruction,
          onChanged: (v) => onEdit(() => cls.instruction = v),
          maxLines: 2,
          style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 12),
          decoration: _dec('What the participant should do'),
        ),
        const SizedBox(height: 10),

        // per-class block timing
        _miniLabel('BLOCK TIMING (s)'),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
              child: _durField('Instruction', cls.instructionSec,
                  (v) => onEdit(() => cls.instructionSec = v))),
          const SizedBox(width: 8),
          Expanded(
              child: _durField(
                  'Active', cls.activeSec, (v) => onEdit(() => cls.activeSec = v))),
          const SizedBox(width: 8),
          Expanded(
              child: _durField(
                  'Reset', cls.resetSec, (v) => onEdit(() => cls.resetSec = v))),
        ]),
        const SizedBox(height: 10),

        // animation
        _miniLabel('REFERENCE ANIMATION'),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(
              cls.animationPath.isEmpty ? 'None' : _basename(cls.animationPath),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.schibstedGrotesk(
                  color: cls.animationPath.isEmpty
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontSize: 11),
            ),
          ),
          if (cls.animationPath.isNotEmpty)
            InkWell(
              onTap: () => onEdit(() => cls.animationPath = ''),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.clear, size: 14, color: AppColors.textSecondary),
              ),
            ),
          TextButton.icon(
            onPressed: () => _pickAnimation(context),
            icon: const Icon(Icons.upload_file, size: 14),
            label: const Text('Upload'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: GoogleFonts.schibstedGrotesk(fontSize: 11),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        // colour
        _miniLabel('THEME COLOUR'),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in kClassPalette)
            InkWell(
              onTap: () => onEdit(() => cls.colorValue = c),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cls.colorValue == c ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),

        // cognitive prompt
        InkWell(
          onTap: () => onEdit(() => cls.cognitivePrompt = !cls.cognitivePrompt),
          child: Row(children: [
            Icon(cls.cognitivePrompt ? Icons.check_box : Icons.check_box_outline_blank,
                size: 16,
                color: cls.cognitivePrompt ? AppColors.accent : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text('Cognitive prompt (e.g. count out loud)',
                style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11)),
          ]),
        ),
        Divider(color: AppColors.border, height: 18),

        // feedback
        Row(children: [
          _miniLabel('FEEDBACK SETTINGS'),
          if (!globalFeedback) ...[
            const SizedBox(width: 6),
            Text('(global off)',
                style: GoogleFonts.schibstedGrotesk(color: AppColors.accentOrange, fontSize: 9)),
          ],
        ]),
        const SizedBox(height: 6),
        _fbRow(Icons.accessibility_new, 'Movement Mirror', cls.feedback.movementMirror,
            (v) => onEdit(() => cls.feedback.movementMirror = v)),
        _fbRow(Icons.compare_arrows, 'Pressure Indicator', cls.feedback.pressureIndicator,
            (v) => onEdit(() => cls.feedback.pressureIndicator = v)),
        _fbRow(Icons.psychology_outlined, 'EEG Feedback', cls.feedback.eegFeedback,
            (v) => onEdit(() => cls.feedback.eegFeedback = v)),
      ]),
    );
  }

  Future<void> _pickAnimation(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gif', 'mp4', 'webp', 'mov', 'webm'],
      dialogTitle: 'Select reference animation',
    );
    final path = result?.files.single.path;
    if (path != null) onEdit(() => cls.animationPath = path);
  }

  /// Pick an authored exercise (avatar guide) from the library for this class.
  Future<void> _pickExercise(
      BuildContext context, ProtocolClass cls, void Function(VoidCallback) onEdit) async {
    final repo = context.read<ExerciseRepository>();
    if (repo.exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No exercises yet — record one in the Exercises section first.')));
      return;
    }
    final chosen = await showDialog<ExerciseAsset>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose an exercise guide'),
        children: [
          for (final e in repo.exercises)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(e),
              child: Row(children: [
                Icon(e.isRecorded ? Icons.animation : Icons.gif_box_outlined,
                    size: 16, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(child: Text(e.name)),
              ]),
            ),
        ],
      ),
    );
    if (chosen != null) {
      onEdit(() {
        cls.exerciseId = chosen.id;
        cls.exerciseType = chosen.name;
      });
    }
  }

  Widget _fbRow(IconData icon, String label, bool value, ValueChanged<bool> onChanged) {
    final enabled = globalFeedback;
    final active = enabled && value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        Icon(icon, size: 14, color: active ? AppColors.accent : AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: GoogleFonts.schibstedGrotesk(
                  color: enabled ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 12)),
        ),
        Transform.scale(
          scale: 0.75,
          child: Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: AppColors.accent,
          ),
        ),
      ]),
    );
  }

  Widget _miniLabel(String s) => Text(s,
      style: GoogleFonts.schibstedGrotesk(
          color: AppColors.textSecondary,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2));

  Widget _durField(String label, double value, ValueChanged<double> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 9)),
        const SizedBox(height: 3),
        TextFormField(
          initialValue: _g(value),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) {
            final d = double.tryParse(v);
            if (d != null && d >= 0) onChanged(d);
          },
          style: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 13),
          decoration: _dec('0').copyWith(
            suffixText: 's',
            suffixStyle: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 10),
          ),
        ),
      ]);

  /// Trim a trailing ".0" so "30.0" shows as "30".
  static String _g(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 11),
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.accent)),
      );

  static String _basename(String p) {
    final parts = p.split(RegExp(r'[\\/]')).where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? p : parts.last;
  }
}

// ── shared card shell ─────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}
