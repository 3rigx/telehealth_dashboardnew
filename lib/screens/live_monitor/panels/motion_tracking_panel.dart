import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../services/unity_connection_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/video_stream_widget.dart';

class MotionTrackingPanel extends StatelessWidget {
  const MotionTrackingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final svc   = context.watch<UnityConnectionService>();
    final state = svc.state;
    final knee  = state.jointAngles.isNotEmpty ? state.jointAngles[0] : null;
    final hip   = state.jointAngles.length > 1  ? state.jointAngles[1] : null;

    return DashboardPanel(
      title: 'Motion Tracking',
      icon: Icons.directions_run,
      child: Column(children: [
        // ── Main view area ────────────────────────────────────────────────
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(fit: StackFit.expand, children: [
                // Background / feed
                svc.useDemoMode
                  ? _SeatedSkeletonView(
                      kneeAngle: knee?.angle ?? 52,
                      hipAngle:  hip?.angle  ?? 88,
                      trunkLean: knee?.trunkLean ?? 4,
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
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
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
                  target: 'Target: ${knee.targetMin?.toInt()}–${knee.targetMax?.toInt()}°',
                  valueColor: knee.inTarget ? AppColors.accentGreen : AppColors.accentOrange,
                  showCheck: knee.inTarget,
                ),
                MetricTile(
                  label: hip?.name ?? 'Hip Angle',
                  value: '${(hip?.angle ?? 0).toStringAsFixed(0)}°',
                  target: 'Target: ${hip?.targetMin?.toInt() ?? 80}–${hip?.targetMax?.toInt() ?? 100}°',
                  valueColor: (hip?.inTarget ?? false) ? AppColors.accentGreen : AppColors.accentOrange,
                  showCheck: hip?.inTarget ?? false,
                ),
                MetricTile(
                  label: 'Repetition Count',
                  value: '${knee.repCount} / ${knee.targetReps}',
                  target: 'Target: ${knee.targetReps}',
                  valueColor: AppColors.textPrimary,
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
      Text('Tracking Confidence', style: GoogleFonts.inter(
        color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w500,
      ), textAlign: TextAlign.center),
      const SizedBox(height: 2),
      Text(isHigh ? 'High' : 'Low', style: GoogleFonts.inter(
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

// ── Seated skeleton view ─────────────────────────────────────────────────────
class _SeatedSkeletonView extends StatefulWidget {
  final double kneeAngle;
  final double hipAngle;
  final double trunkLean;
  const _SeatedSkeletonView({
    required this.kneeAngle,
    required this.hipAngle,
    required this.trunkLean,
  });

  @override
  State<_SeatedSkeletonView> createState() => _SeatedSkeletonViewState();
}

class _SeatedSkeletonViewState extends State<_SeatedSkeletonView>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _SeatedSkeletonPainter(
          kneeAngle: widget.kneeAngle,
          hipAngle: widget.hipAngle,
          trunkLean: widget.trunkLean,
          tick: _ctrl.value,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SeatedSkeletonPainter extends CustomPainter {
  final double kneeAngle;
  final double hipAngle;
  final double trunkLean;
  final double tick;

  const _SeatedSkeletonPainter({
    required this.kneeAngle,
    required this.hipAngle,
    required this.trunkLean,
    required this.tick,
  });

  // ── colours ───────────────────────────────────────────────────────────
  static const _bg          = Color(0xFF060C1A);
  static const _bone        = Color(0xFF1A6EFA);
  static const _bonePop     = Color(0xFF4D94FF);
  static const _jointFill   = Color(0xFF00D4FF);
  static const _jointHi     = Color(0xFF00C896);
  static const _angleArc    = Color(0xFFFFAA00);
  static const _chairCol    = Color(0xFF192B47);
  static const _bodyFill    = Color(0xFF0D2040);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;

    // ── background ────────────────────────────────────────────────────
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    // Subtle dot-grid
    final gridPaint = Paint()..color = AppColors.border.withValues(alpha: 0.25);
    for (double gx = 20; gx < w; gx += 30) {
      for (double gy = 20; gy < h; gy += 30) {
        canvas.drawCircle(Offset(gx, gy), 1, gridPaint);
      }
    }

    // ── compute body positions ─────────────────────────────────────────
    // Figure occupies roughly left 60% of panel; right 40% is open space.
    // Origin is figure's hip joint.
    final hipX   = w * 0.30;
    final hipY   = h * 0.60;
    final scale  = h * 0.18; // size unit

    // Trunk lean (slight forward tilt)
    final leanRad = (trunkLean * pi / 180).clamp(-0.3, 0.5);

    // Key body joints (side-profile, figure faces right)
    final hip       = Offset(hipX, hipY);
    final waist     = hip     + _polar(scale * 0.30, -pi / 2 + leanRad);
    final chest     = waist   + _polar(scale * 0.55, -pi / 2 + leanRad);
    final shoulder  = chest   + _polar(scale * 0.15, -pi / 2 + leanRad);
    final neck      = shoulder + _polar(scale * 0.18, -pi / 2 + leanRad * 0.5);
    final head      = neck    + _polar(scale * 0.20, -pi / 2);

    // Arm (near side)
    final elbow     = shoulder + _polar(scale * 0.55, pi / 4 + leanRad);
    final wrist     = elbow   + _polar(scale * 0.45, pi / 3);

    // Thigh (horizontal forward from hip)
    const thighLen  = 1.35; // scale units
    final knee      = hip + Offset(scale * thighLen, 0);

    // Lower leg — kneeAngle: 0° = fully extended (horizontal), 90° = straight down
    // In the reference the leg is at ~52°, going downward-forward from knee
    final kRad      = (kneeAngle * pi / 180.0).clamp(0.0, pi);
    final lowerLen  = scale * 1.20;
    final ankle     = knee + _polar(lowerLen, kRad);
    final toeEnd    = ankle + _polar(scale * 0.35, 0);
    final heelEnd   = ankle + _polar(scale * 0.12, pi);

    // ── draw chair ────────────────────────────────────────────────────
    final chairP = Paint()
      ..color = _chairCol
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Seat (horizontal plank)
    final seatTop  = hipY + scale * 0.05;
    final seatLeft = hipX - scale * 0.25;
    final seatRgt  = knee.dx + scale * 0.05;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(seatLeft, seatTop - 4, seatRgt, seatTop + 6),
        const Radius.circular(3),
      ),
      Paint()..color = _chairCol.withValues(alpha: 0.9),
    );

    // Backrest
    canvas.drawLine(
      Offset(seatLeft + 4, seatTop - 4),
      Offset(seatLeft + 4, seatTop - scale * 1.4),
      chairP..strokeWidth = 5,
    );
    // Top rail
    canvas.drawLine(
      Offset(seatLeft - 4, seatTop - scale * 1.4),
      Offset(seatLeft + 20, seatTop - scale * 1.4),
      chairP,
    );

    // Chair front legs
    canvas.drawLine(
      Offset(seatRgt - 10, seatTop + 6),
      Offset(seatRgt,      h * 0.96),
      chairP..strokeWidth = 4,
    );
    canvas.drawLine(
      Offset(seatLeft + 16, seatTop + 6),
      Offset(seatLeft + 8,  h * 0.96),
      chairP..strokeWidth = 4,
    );

    // Floor line
    canvas.drawLine(
      Offset(seatLeft - 10, h * 0.96),
      Offset(w * 0.80, h * 0.96),
      Paint()..color = AppColors.border.withValues(alpha: 0.4)..strokeWidth = 1,
    );

    // ── body silhouette (subtle filled shape) ─────────────────────────
    final bodyPath = Path()
      ..moveTo(head.dx, head.dy - scale * 0.22)   // top of head
      ..cubicTo(
        head.dx + scale * 0.18, head.dy - scale * 0.22,
        shoulder.dx + scale * 0.20, shoulder.dy,
        shoulder.dx + scale * 0.20, shoulder.dy,
      )
      ..lineTo(hip.dx + scale * 0.18, hipY)
      ..cubicTo(
        hip.dx + scale * 0.18, hipY + scale * 0.15,
        hip.dx - scale * 0.12, hipY + scale * 0.15,
        hip.dx - scale * 0.12, hipY,
      )
      ..lineTo(shoulder.dx - scale * 0.18, shoulder.dy)
      ..cubicTo(
        shoulder.dx - scale * 0.18, shoulder.dy,
        head.dx - scale * 0.18, head.dy - scale * 0.22,
        head.dx, head.dy - scale * 0.22,
      )
      ..close();
    canvas.drawPath(bodyPath, Paint()
      ..color = _bodyFill.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill);

    // ── skeleton lines ────────────────────────────────────────────────
    final bonePaint = Paint()
      ..color = _bone
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    final highlightBone = Paint()
      ..color = _bonePop
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    void line(Offset a, Offset b, [bool hi = false]) =>
        canvas.drawLine(a, b, hi ? highlightBone : bonePaint);

    // Spine
    line(hip, waist);
    line(waist, chest);
    line(chest, shoulder);
    line(shoulder, neck);

    // Arm
    line(shoulder, elbow);
    line(elbow, wrist);

    // Legs — highlighted in slightly different tone
    line(hip, knee, true);
    line(knee, ankle, true);
    // Foot
    line(heelEnd, toeEnd, true);

    // Head (circle outline)
    canvas.drawCircle(head, scale * 0.22, Paint()
      ..color = _bone
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6);

    // ── knee angle arc annotation ─────────────────────────────────────
    const arcR = 44.0;
    final arcRect = Rect.fromCenter(center: knee, width: arcR * 2, height: arcR * 2);
    // Sweep from thigh direction (0 rad = pointing right) by kRad downward
    canvas.drawArc(arcRect, 0, kRad, false, Paint()
      ..color = _angleArc
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round);

    // Tick marks at start and end of arc
    canvas.drawLine(
      knee + _polar(arcR - 5, 0),
      knee + _polar(arcR + 5, 0),
      Paint()..color = _angleArc..strokeWidth = 1.5,
    );
    canvas.drawLine(
      knee + _polar(arcR - 5, kRad),
      knee + _polar(arcR + 5, kRad),
      Paint()..color = _angleArc..strokeWidth = 1.5,
    );

    // Angle text
    final midAngle = kRad / 2;
    final labelPos = knee + _polar(arcR + 18, midAngle) + const Offset(-6, -8);
    _paintText(canvas, '${kneeAngle.toStringAsFixed(0)}°', labelPos,
      const TextStyle(color: _angleArc, fontSize: 15, fontWeight: FontWeight.w700));

    // ── joints ────────────────────────────────────────────────────────
    void joint(Offset p, {double r = 4.5, bool highlight = false}) {
      canvas.drawCircle(p, r, Paint()..color = highlight ? _jointHi : _jointFill);
      canvas.drawCircle(p, r, Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2);
    }

    joint(neck);
    joint(shoulder);
    joint(elbow);
    joint(wrist);
    joint(hip, r: 5.5);
    joint(ankle);
    joint(knee, r: 7.5, highlight: true);  // knee is the primary joint

    // ── animated scan-line pulse ──────────────────────────────────────
    final pulse = (sin(tick * 2 * pi) + 1) / 2;
    canvas.drawRect(
      Rect.fromLTWH(0, h * pulse * 0.94, w, 1.5),
      Paint()..color = _bone.withValues(alpha: 0.08 * pulse),
    );
  }

  static Offset _polar(double r, double angle) =>
      Offset(r * cos(angle), r * sin(angle));

  static void _paintText(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(_SeatedSkeletonPainter old) =>
      old.kneeAngle != kneeAngle ||
      old.trunkLean != trunkLean ||
      old.tick != tick;
}
