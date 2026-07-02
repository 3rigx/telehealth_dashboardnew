import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../services/unity_connection_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/video_stream_widget.dart';
import '../../../widgets/skeleton_3d_view.dart';

class MotionTrackingPanel extends StatefulWidget {
  const MotionTrackingPanel({super.key});

  @override
  State<MotionTrackingPanel> createState() => _MotionTrackingPanelState();
}

class _MotionTrackingPanelState extends State<MotionTrackingPanel> {
  bool _showVideo = false; // false = native 3D skeleton, true = camera video

  // Target range label, or null when the exercise hasn't supplied a target yet.
  static String? _targetLabel(double? min, double? max) =>
      (min != null && max != null) ? 'Target: ${min.toInt()}–${max.toInt()}°' : null;

  @override
  Widget build(BuildContext context) {
    final svc   = context.watch<UnityConnectionService>();
    final state = svc.state;
    final knee  = state.jointAngles.isNotEmpty ? state.jointAngles[0] : null;
    final hip   = state.jointAngles.length > 1  ? state.jointAngles[1] : null;
    final has3d = state.skeleton != null;
    final show3d = has3d && !_showVideo;

    return DashboardPanel(
      title: 'Motion Tracking',
      icon: Icons.directions_run,
      trailing: has3d ? _ViewToggle(
        showVideo: _showVideo,
        onChanged: (v) => setState(() => _showVideo = v),
      ) : null,
      child: Column(children: [
        // ── Main view area ────────────────────────────────────────────────
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(fit: StackFit.expand, children: [
                // Background / feed — native 3D skeleton when joint coords are
                // available and selected; otherwise the raw + overlay video feeds.
                show3d
                  ? Skeleton3DView(
                      skeleton: state.skeleton!,
                      targetMin: knee?.targetMin,
                      targetMax: knee?.targetMax,
                    )
                  : Stack(fit: StackFit.expand, children: [
                      const VideoStreamWidget(
                        url: 'http://localhost:8766/raw',
                        label: 'ZED Camera (Raw)',
                      ),
                      Positioned.fill(
                        child: const VideoStreamWidget(
                          url: 'http://localhost:8766/overlay',
                          label: 'Skeleton Overlay',
                        ),
                      ),
                    ]),
                // "ZED Movement View (Live)" label overlay
                Positioned(
                  top: 8, left: 10,
                  child: Text(
                    'ZED Movement View (Live)',
                    style: GoogleFonts.schibstedGrotesk(
                      color: AppColors.inkMuted.withValues(alpha: 0.7),
                      fontSize: 9,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        // ── Metrics row ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (knee != null) ...[
                MetricTile(
                  label: knee.name,
                  value: '${knee.angle.toStringAsFixed(0)}°',
                  target: _targetLabel(knee.targetMin, knee.targetMax),
                  valueColor: knee.inTarget ? AppColors.accentGreen : AppColors.accentOrange,
                  showCheck: knee.inTarget,
                ),
                MetricTile(
                  label: hip?.name ?? 'Hip Angle',
                  value: '${(hip?.angle ?? 0).toStringAsFixed(0)}°',
                  target: _targetLabel(hip?.targetMin, hip?.targetMax),
                  valueColor: (hip?.inTarget ?? false) ? AppColors.accentGreen : AppColors.accentOrange,
                  showCheck: hip?.inTarget ?? false,
                ),
                MetricTile(
                  label: 'Repetition Count',
                  value: '${knee.repCount} / ${knee.targetReps}',
                  target: 'Target: ${knee.targetReps}',
                  valueColor: AppColors.inkText,
                ),
                _ConfidenceTile(confidence: knee.trackingConfidence),
                MetricTile(
                  label: 'Trunk Lean',
                  value: '${knee.trunkLean.toStringAsFixed(0)}°',
                  target: 'Target: < 10°',
                  valueColor: knee.trunkLean < 10 ? AppColors.accentGreen : AppColors.accentOrange,
                  showCheck: knee.trunkLean < 10,
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

// ── 3D / Video segmented toggle (panel header) ───────────────────────────────
class _ViewToggle extends StatelessWidget {
  final bool showVideo;
  final ValueChanged<bool> onChanged;
  const _ViewToggle({required this.showVideo, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.inkBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.inkBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _seg('3D', !showVideo, () => onChanged(false), Icons.threed_rotation),
        _seg('Video', showVideo, () => onChanged(true), Icons.videocam),
      ]),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap, IconData icon) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11,
              color: active ? Colors.white : AppColors.inkMuted),
          const SizedBox(width: 3),
          Text(label, style: GoogleFonts.schibstedGrotesk(
            color: active ? Colors.white : AppColors.inkMuted,
            fontSize: 10, fontWeight: FontWeight.w600,
          )),
        ]),
      ),
    );
  }
}

// ── Confidence tile with bar visualisation ───────────────────────────────────
class _ConfidenceTile extends StatelessWidget {
  final double confidence; // 0..1
  const _ConfidenceTile({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final isHigh = confidence >= 0.8;
    final color  = isHigh ? AppColors.accentGreen : AppColors.accentOrange;
    const bars   = 8;
    final filled = (confidence * bars).round().clamp(0, bars);

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Tracking Confidence', style: GoogleFonts.schibstedGrotesk(
        color: AppColors.inkMuted, fontSize: 10, fontWeight: FontWeight.w500,
      ), textAlign: TextAlign.center),
      const SizedBox(height: 2),
      Text(isHigh ? 'High' : 'Low', style: GoogleFonts.schibstedGrotesk(
        color: color, fontSize: 20, fontWeight: FontWeight.w700,
      )),
      const SizedBox(height: 3),
      Row(mainAxisSize: MainAxisSize.min, children: List.generate(bars, (i) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Container(
            width: 7, height: 10,
            decoration: BoxDecoration(
              color: i < filled ? color : color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ),
      )),
    ]);
  }
}
