import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/telerehab_state.dart';
import '../theme/app_theme.dart';

/// Anatomical four-zone foot pressure heatmap with center-of-pressure marker.
/// Shared by the live plantar panel and the replay screen. Zones must be
/// normalised 0..1.
class FootHeatmap extends StatelessWidget {
  final String label;
  final FootZones zones;
  final bool isLeft;

  /// Optional COP trail (normalised foot coords) drawn as a fading polyline —
  /// used by replay to show sway over the last few seconds.
  final List<Offset> copTrail;

  const FootHeatmap({
    super.key,
    required this.label,
    required this.zones,
    required this.isLeft,
    this.copTrail = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label,
          style: GoogleFonts.schibstedGrotesk(
              color: AppColors.inkMuted, fontSize: 10, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Expanded(
        child: CustomPaint(
          painter: _FootPainter(zones: zones, isLeft: isLeft, copTrail: copTrail),
          child: const SizedBox.expand(),
        ),
      ),
    ]);
  }
}

class _FootPainter extends CustomPainter {
  final FootZones zones;
  final bool isLeft;
  final List<Offset> copTrail;
  _FootPainter({required this.zones, required this.isLeft, required this.copTrail});

  static Color heat(double v) {
    v = v.clamp(0.0, 1.0);
    if (v < 0.20) return Color.lerp(const Color(0xFF0033CC), const Color(0xFF0099FF), v / 0.20)!;
    if (v < 0.40) return Color.lerp(const Color(0xFF0099FF), const Color(0xFF00DDAA), (v - 0.20) / 0.20)!;
    if (v < 0.60) return Color.lerp(const Color(0xFF00DDAA), const Color(0xFFAAFF00), (v - 0.40) / 0.20)!;
    if (v < 0.80) return Color.lerp(const Color(0xFFAAFF00), const Color(0xFFFFAA00), (v - 0.60) / 0.20)!;
    return Color.lerp(const Color(0xFFFFAA00), const Color(0xFFFF1100), (v - 0.80) / 0.20)!;
  }

  Offset _toe() => const Offset(0.50, 0.13);
  Offset _heel() => const Offset(0.50, 0.85);
  Offset _inner() => Offset(isLeft ? 0.66 : 0.34, 0.48);
  Offset _outer() => Offset(isLeft ? 0.34 : 0.66, 0.48);

  Path _outline(double w, double h) {
    final medX = isLeft ? w * 0.85 : w * 0.15;
    final latX = isLeft ? w * 0.15 : w * 0.85;
    final path = Path();
    path.moveTo(latX, h * 0.02);
    path.quadraticBezierTo(w * 0.50, h * -0.04, medX, h * 0.02);
    path.cubicTo(
      medX + (isLeft ? -w * 0.05 : w * 0.05), h * 0.30,
      medX + (isLeft ? -w * 0.20 : w * 0.20), h * 0.52,
      medX + (isLeft ? -w * 0.10 : w * 0.10), h * 0.72,
    );
    path.quadraticBezierTo(medX, h * 0.90, w * 0.50, h * 0.98);
    path.quadraticBezierTo(latX, h * 0.90, latX + (isLeft ? w * 0.05 : -w * 0.05), h * 0.70);
    path.cubicTo(latX, h * 0.55, latX, h * 0.30, latX, h * 0.02);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final footPath = _outline(w, h);

    canvas.save();
    canvas.clipPath(footPath);
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0033CC).withValues(alpha: 0.22));

    final blobs = <(Offset, double, String)>[
      (_toe(), zones.toe, 'Toe'),
      (_inner(), zones.medial, 'Medial'),
      (_outer(), zones.lateral, 'Lateral'),
      (_heel(), zones.heel, 'Heel'),
    ];

    for (final (pos, v, _) in blobs) {
      if (v <= 0.02) continue;
      final c = Offset(pos.dx * w, pos.dy * h);
      final r = w * 0.42 * (0.55 + v * 0.6);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              heat(v).withValues(alpha: (0.75 * v + 0.2).clamp(0.0, 0.9)),
              heat(v).withValues(alpha: 0.0),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }

    for (final (pos, v, name) in blobs) {
      final c = Offset(pos.dx * w, pos.dy * h);
      _text(canvas, name, c.translate(0, -7), 8.5, Colors.white.withValues(alpha: 0.65));
      _text(canvas, '${(v * 100).round()}', c.translate(0, 4), 11,
          Colors.white.withValues(alpha: 0.95), bold: true);
    }

    // COP trail (oldest → newest, fading in)
    if (copTrail.length > 1) {
      for (var i = 1; i < copTrail.length; i++) {
        final k = i / copTrail.length;
        canvas.drawLine(
          Offset(copTrail[i - 1].dx * w, copTrail[i - 1].dy * h),
          Offset(copTrail[i].dx * w, copTrail[i].dy * h),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.5 * k)
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // COP marker
    final total = zones.sum;
    if (total > 0.04) {
      double cx = 0, cy = 0;
      for (final (pos, v, _) in blobs) {
        cx += pos.dx * v;
        cy += pos.dy * v;
      }
      final cop = Offset(cx / total * w, cy / total * h);
      canvas.drawCircle(cop, 7, Paint()..color = Colors.white.withValues(alpha: 0.25));
      canvas.drawCircle(cop, 4, Paint()..color = Colors.white);
      canvas.drawCircle(
          cop,
          4,
          Paint()
            ..color = AppColors.accentRed
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6);
    }
    canvas.restore();

    canvas.drawPath(
        footPath,
        Paint()
          ..color = AppColors.inkBorder.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
  }

  void _text(Canvas c, String s, Offset center, double size, Color color, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: GoogleFonts.schibstedGrotesk(
              color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_FootPainter old) =>
      old.zones != zones || old.isLeft != isLeft || old.copTrail != copTrail;
}
