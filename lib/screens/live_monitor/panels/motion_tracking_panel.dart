import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../services/unity_connection_service.dart';
import '../../../models/telerehab_state.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/video_stream_widget.dart';

class MotionTrackingPanel extends StatelessWidget {
  const MotionTrackingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<UnityConnectionService>().state;
    final knee = state.jointAngles.isNotEmpty ? state.jointAngles[0] : null;
    final hip  = state.jointAngles.length > 1  ? state.jointAngles[1] : null;

    return DashboardPanel(
      title: 'Motion Tracking',
      icon: Icons.directions_run,
      child: Column(children: [
        // Video streams — raw ZED feed + Unity overlay side by side
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(children: [
              // Raw ZED camera feed
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(fit: StackFit.expand, children: [
                      const VideoStreamWidget(
                        url: 'http://localhost:8766/raw',
                        label: 'ZED Camera (Raw)',
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Unity skeleton overlay
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(fit: StackFit.expand, children: [
                      const VideoStreamWidget(
                        url: 'http://localhost:8766/overlay',
                        label: 'Skeleton Overlay',
                      ),
                      // Angle gauge on top of video
                      if (knee != null)
                        Positioned(
                          right: 8, top: 8,
                          child: _AngleGauge(knee.angle,
                              knee.targetMin ?? 40, knee.targetMax ?? 60),
                        ),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
        // Metrics row
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (knee != null) ...[
                MetricTile(
                  label: knee.name,
                  value: '${knee.angle.toStringAsFixed(0)}°',
                  target: 'Target: ${knee.targetMin?.toInt()}–${knee.targetMax?.toInt()}°',
                  valueColor: knee.inTarget ? AppColors.accentGreen : AppColors.accentOrange,
                ),
                MetricTile(
                  label: hip?.name ?? 'Hip Angle',
                  value: '${(hip?.angle ?? 0).toStringAsFixed(0)}°',
                  target: 'Target: ${hip?.targetMin?.toInt() ?? 80}–${hip?.targetMax?.toInt() ?? 100}°',
                  valueColor: (hip?.inTarget ?? false) ? AppColors.accentGreen : AppColors.accentOrange,
                ),
                MetricTile(
                  label: 'Rep Count',
                  value: '${knee.repCount} / ${knee.targetReps}',
                  target: 'Target: ${knee.targetReps}',
                  valueColor: AppColors.textPrimary,
                ),
              ],
              MetricTile(
                label: 'Tracking',
                value: knee != null
                  ? (knee.trackingConfidence > 0.8 ? 'High' : 'Low')
                  : 'N/A',
                valueColor: knee != null && knee.trackingConfidence > 0.8
                  ? AppColors.accentGreen : AppColors.accentOrange,
              ),
              if (knee != null)
                MetricTile(
                  label: 'Trunk Lean',
                  value: '${knee.trunkLean.toStringAsFixed(0)}°',
                  target: 'Target: < 10°',
                  valueColor: knee.trunkLean < 10 ? AppColors.accentGreen : AppColors.accentOrange,
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Animated stick-figure skeleton ──────────────────────────────────────────
class _SkeletonView extends StatefulWidget {
  const _SkeletonView();
  @override
  State<_SkeletonView> createState() => _SkeletonViewState();
}

class _SkeletonViewState extends State<_SkeletonView>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<UnityConnectionService>().state;
    final kneeAngle = state.jointAngles.isNotEmpty
      ? state.jointAngles[0].angle : 90.0;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _SkeletonPainter(kneeAngle),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  final double kneeAngle;
  _SkeletonPainter(this.kneeAngle);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final scale = size.height / 4.5;

    // Joint positions (simplified seated figure)
    final head     = Offset(cx, scale * 0.3);
    final neck     = Offset(cx, scale * 0.55);
    final shoulder = Offset(cx, scale * 0.75);
    final lShoulder= Offset(cx - scale * 0.4, scale * 0.75);
    final rShoulder= Offset(cx + scale * 0.4, scale * 0.75);
    final lElbow   = Offset(cx - scale * 0.55, scale * 1.15);
    final rElbow   = Offset(cx + scale * 0.55, scale * 1.15);
    final lWrist   = Offset(cx - scale * 0.5, scale * 1.55);
    final rWrist   = Offset(cx + scale * 0.5, scale * 1.55);
    final hip      = Offset(cx, scale * 1.4);
    final lHip     = Offset(cx - scale * 0.28, scale * 1.4);
    final rHip     = Offset(cx + scale * 0.28, scale * 1.4);

    // Knee driven by angle
    final kneeFraction = (kneeAngle - 0) / 180.0;
    final lKnee = lHip + Offset(-scale * 0.05, scale * (0.7 + kneeFraction * 0.3));
    final rKnee = rHip + Offset( scale * 0.05, scale * (0.7 + kneeFraction * 0.3));
    final lFoot = lKnee + Offset(-scale * 0.2,  scale * 0.5);
    final rFoot = rKnee + Offset( scale * 0.2,  scale * 0.5);

    final bonePaint = Paint()
      ..color = const Color(0xFF1A6EFA).withOpacity(0.9)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final jointPaint = Paint()
      ..color = const Color(0xFF00D4FF)
      ..style = PaintingStyle.fill;

    final highlightPaint = Paint()
      ..color = const Color(0xFF00C896)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    void bone(Offset a, Offset b, [bool highlight = false]) {
      canvas.drawLine(a, b, highlight ? highlightPaint : bonePaint);
    }

    void joint(Offset p, [double r = 5]) {
      canvas.drawCircle(p, r, jointPaint);
      canvas.drawCircle(p, r, Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
    }

    // Spine
    bone(head, neck); bone(neck, shoulder); bone(shoulder, hip);
    // Arms
    bone(lShoulder, lElbow); bone(lElbow, lWrist);
    bone(rShoulder, rElbow); bone(rElbow, rWrist);
    // Legs (highlight knee joint)
    bone(lHip, lKnee, true); bone(lKnee, lFoot, true);
    bone(rHip, rKnee, true); bone(rKnee, rFoot, true);

    // Draw joints
    for (final p in [head, neck, lShoulder, rShoulder, lElbow, rElbow,
                     lWrist, rWrist, lHip, rHip, lFoot, rFoot]) {
      joint(p, 4);
    }
    // Highlighted knee joints
    joint(lKnee, 7); joint(rKnee, 7);

    // Head circle
    canvas.drawCircle(head - const Offset(0, 12), 12, bonePaint..style = PaintingStyle.stroke);

    // Angle arc at right knee
    final arcRect = Rect.fromCenter(center: rKnee, width: 40, height: 40);
    canvas.drawArc(arcRect, -pi / 2, (kneeAngle / 180) * pi, false,
      Paint()..color = const Color(0xFFFFAA00).withOpacity(0.7)
             ..style = PaintingStyle.stroke
             ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => old.kneeAngle != kneeAngle;
}

// ── Angle gauge widget ───────────────────────────────────────────────────────
class _AngleGauge extends StatelessWidget {
  final double angle;
  final double min;
  final double max;
  const _AngleGauge(this.angle, this.min, this.max);

  @override
  Widget build(BuildContext context) {
    final inRange = angle >= min && angle <= max;
    return Container(
      width: 70, height: 70,
      decoration: BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
        border: Border.all(
          color: inRange ? AppColors.accentGreen : AppColors.accentOrange,
          width: 2,
        ),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('${angle.toStringAsFixed(0)}°',
          style: GoogleFonts.inter(
            color: inRange ? AppColors.accentGreen : AppColors.accentOrange,
            fontSize: 18, fontWeight: FontWeight.w700,
          )),
        Text('knee', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 9)),
      ]),
    ).animate(onPlay: (c) => c.repeat(reverse: true))
     .custom(duration: 800.ms, builder: (_, v, child) =>
       Transform.scale(scale: 1.0 + (!inRange ? v * 0.03 : 0), child: child));
  }
}
