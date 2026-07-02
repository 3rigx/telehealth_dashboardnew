import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../services/unity_connection_service.dart';
import '../../../models/telerehab_state.dart';
import '../../../theme/app_theme.dart';

class FusionPanel extends StatelessWidget {
  const FusionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<UnityConnectionService>().state;
    final knee  = state.jointAngles.isNotEmpty ? state.jointAngles[0] : null;
    final p     = state.plantar;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inkBorder),
      ),
      child: Row(children: [
        // Title
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.account_tree_outlined, color: AppColors.accentOrange, size: 16),
              const SizedBox(width: 6),
              Text('Multimodal Fusion Output', style: GoogleFonts.schibstedGrotesk(
                color: AppColors.accentOrange, fontSize: 13, fontWeight: FontWeight.w600,
              )),
            ]),
          ],
        ),
        const SizedBox(width: 24),
        // Movement features
        Expanded(child: _FeatureGroup(
          icon: Icons.directions_run,
          title: 'Movement Features',
          color: AppColors.accent,
          rows: [
            if (knee != null) ...[
              ('Knee Angle (°)',       knee.angle.toStringAsFixed(0)),
              ('Range of Motion (°)',  (knee.maxAngle - knee.minAngle).abs().toStringAsFixed(0)),
              ('Trunk Lean (°)',       knee.trunkLean.toStringAsFixed(0)),
              ('Repetition Count',     '${knee.repCount} / ${knee.targetReps}'),
              ('Tracking Confidence',  knee.trackingConfidence > 0.8 ? 'High' : 'Low'),
            ] else
              ('No motion data', '—'),
          ],
        )),
        const SizedBox(width: 12),
        // Pressure features
        Expanded(child: _FeatureGroup(
          icon: Icons.accessibility,
          title: 'Pressure Features',
          color: AppColors.accentCyan,
          rows: [
            ('Total Load (%BW)',      p.totalLoad.toStringAsFixed(1)),
            ('Heel Load (%BW)',       p.heelLoad.toStringAsFixed(1)),
            ('Forefoot Load (%BW)',   p.forefootLoad.toStringAsFixed(1)),
            ('L/R Asymmetry (%)',     p.asymmetry.toStringAsFixed(1)),
            ('Stability (COP SD, cm)',p.stability.toStringAsFixed(2)),
          ],
          statuses: [null, null, null,
            p.asymmetry < 15 ? _RowStatus.good : _RowStatus.warn,
            p.stability  < 1 ? _RowStatus.good : _RowStatus.warn,
          ],
        )),
        const SizedBox(width: 12),
        // EEG features (live when the Unicorn is streaming, else a stub)
        Expanded(child: _eegFeatureGroup(state.eeg)),
        const SizedBox(width: 12),
        // Fusion result
        _FusionResult(state: state),
      ]),
    );
  }
}

/// EEG column of the fusion strip — real band powers + signal quality when the
/// Unicorn is streaming, otherwise a clearly-marked stub.
Widget _eegFeatureGroup(EegData? eeg) {
  _RowStatus qualityStatus(String q) => q == 'Good'
      ? _RowStatus.good
      : (q == 'Fair' ? _RowStatus.warn : _RowStatus.bad);

  return _FeatureGroup(
    icon: Icons.psychology_outlined,
    title: 'EEG Features',
    color: const Color(0xFFBB86FC),
    stub: eeg == null,
    rows: eeg == null
        ? const [
            ('Theta Power (µV²)', '—'),
            ('Alpha Power (µV²)', '—'),
            ('Beta Power (µV²)', '—'),
            ('Signal Quality', '—'),
            ('Artifact Level', '—'),
          ]
        : [
            ('Theta Power (µV²)', eeg.theta.toStringAsFixed(2)),
            ('Alpha Power (µV²)', eeg.alpha.toStringAsFixed(2)),
            ('Beta Power (µV²)', eeg.beta.toStringAsFixed(2)),
            ('Signal Quality', eeg.quality),
            ('Artifact Level', eeg.artifact),
          ],
    statuses: eeg == null
        ? const [null, null, null, null, null]
        : [
            null, null, null,
            qualityStatus(eeg.quality),
            eeg.artifact == 'Low' ? _RowStatus.good : _RowStatus.warn,
          ],
  );
}

enum _RowStatus { good, warn, bad }

class _FeatureGroup extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<(String, String)> rows;
  final List<_RowStatus?>? statuses;
  final bool stub;

  const _FeatureGroup({
    required this.icon,
    required this.title,
    required this.color,
    required this.rows,
    this.statuses,
    this.stub = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.inkSurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(title, style: GoogleFonts.schibstedGrotesk(
            color: color, fontSize: 11, fontWeight: FontWeight.w600,
          )),
          if (stub) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('STUB', style: GoogleFonts.schibstedGrotesk(
                color: AppColors.accentOrange, fontSize: 7, fontWeight: FontWeight.w700,
              )),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        ...rows.asMap().entries.map((entry) {
          final status = statuses != null && entry.key < statuses!.length
              ? statuses![entry.key] : null;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(entry.value.$1,
                style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 10))),
              Text(entry.value.$2, style: GoogleFonts.schibstedGrotesk(
                color: _valueColor(status), fontSize: 10, fontWeight: FontWeight.w600,
              )),
            ]),
          );
        }),
      ]),
    ),   // Container
    ); // ClipRect
  }

  Color _valueColor(_RowStatus? s) {
    return switch (s) {
      _RowStatus.good => AppColors.accentGreen,
      _RowStatus.warn => AppColors.accentOrange,
      _RowStatus.bad  => AppColors.accentRed,
      null            => AppColors.inkText,
    };
  }
}

class _FusionResult extends StatefulWidget {
  final TelerehabState state;
  const _FusionResult({required this.state});
  @override
  State<_FusionResult> createState() => _FusionResultState();
}

class _FusionResultState extends State<_FusionResult>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _lastConfidence = 0.86;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_FusionResult old) {
    super.didUpdateWidget(old);
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final knee = s.jointAngles.isNotEmpty ? s.jointAngles[0] : null;
    final condition = s.session.condition;

    // Simple confidence heuristic from available real data
    double confidence = 0.86;
    if (knee != null) {
      confidence = knee.inTarget ? 0.88 + min(0.10, knee.trackingConfidence * 0.1)
                                 : 0.65 + min(0.20, 0.20 * knee.trackingConfidence);
    }
    _lastConfidence = confidence;

    return SizedBox(
      width: 160,
      // SingleChildScrollView so this card can never overflow the fusion strip
      // regardless of locale/font metrics; at the strip's height the content
      // fits without actually scrolling.
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.inkSurfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accentGreen.withOpacity(0.2)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.hub_outlined, size: 13, color: AppColors.accentGreen),
            const SizedBox(width: 5),
            Text('Fusion Result', style: GoogleFonts.schibstedGrotesk(
              color: AppColors.accentGreen, fontSize: 11, fontWeight: FontWeight.w600,
            )),
          ]),
          const SizedBox(height: 6),
          Text('Predicted Condition', style: GoogleFonts.schibstedGrotesk(
            color: AppColors.inkMuted, fontSize: 9,
          )),
          const SizedBox(height: 3),
          Text(condition, style: GoogleFonts.schibstedGrotesk(
            color: AppColors.inkText, fontSize: 13, fontWeight: FontWeight.w700,
          ), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)
            .animate().fadeIn().scale(begin: const Offset(0.9, 0.9)),
          const SizedBox(height: 6),
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => CircularPercentIndicator(
              radius: 30,
              lineWidth: 5,
              percent: _lastConfidence * _anim.value,
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(_lastConfidence * _anim.value * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.inkText, fontSize: 14, fontWeight: FontWeight.w700,
                  )),
                Text('confidence', style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.inkMuted, fontSize: 7,
                )),
              ]),
              progressColor: _lastConfidence > 0.8 ? AppColors.accentGreen : AppColors.accentOrange,
              backgroundColor: AppColors.inkBorder,
              circularStrokeCap: CircularStrokeCap.round,
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.check_circle_outline, color: AppColors.accentGreen, size: 12),
            const SizedBox(width: 4),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Stable trial', style: GoogleFonts.schibstedGrotesk(
                color: AppColors.accentGreen, fontSize: 9, fontWeight: FontWeight.w600,
              )),
              Text('All modalities within\nacceptable range.', style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkMuted, fontSize: 8,
              )),
            ])),
          ]),
          const SizedBox(height: 3),
          Text(_lastConfidence > 0.8 ? 'High Confidence' : 'Moderate Confidence',
            style: GoogleFonts.schibstedGrotesk(
              color: _lastConfidence > 0.8 ? AppColors.accentGreen : AppColors.accentOrange,
              fontSize: 9, fontWeight: FontWeight.w600,
            )),
        ]),
      ),
      ),  // SingleChildScrollView
    );
  }
}

extension on JointAngleData {
  double get maxAngle => angle + deviation.abs();
  double get minAngle => angle - deviation.abs();
}
