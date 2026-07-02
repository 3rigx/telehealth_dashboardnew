import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Participant-facing EEG feedback: a top-down head with the 8 Unicorn
/// electrodes (Fz, C3, Cz, C4, Pz, PO7, Oz, PO8) drawn at their 10-20
/// positions. Each point's size/colour tracks that channel's live activity
/// (per-channel RMS from [channels]); a gentle pulse keeps it alive even when
/// values are steady. This is a visualisation, not neurofeedback.
class EegChannelMap extends StatefulWidget {
  /// Per-channel magnitudes, length 8 (Unicorn order). Empty = no signal.
  final List<double> channels;
  const EegChannelMap({super.key, required this.channels});

  @override
  State<EegChannelMap> createState() => _EegChannelMapState();
}

class _EegChannelMapState extends State<EegChannelMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => CustomPaint(
        painter: _HeadPainter(channels: widget.channels, phase: _pulse.value),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _HeadPainter extends CustomPainter {
  final List<double> channels;
  final double phase; // 0..1 pulse phase
  _HeadPainter({required this.channels, required this.phase});

  // 10-20 positions on a top-down head (x: 0..1 left→right, y: 0..1 front→back),
  // in Unicorn channel order.
  static const List<(String, Offset)> _layout = [
    ('Fz', Offset(0.50, 0.27)),
    ('C3', Offset(0.30, 0.50)),
    ('Cz', Offset(0.50, 0.50)),
    ('C4', Offset(0.70, 0.50)),
    ('Pz', Offset(0.50, 0.70)),
    ('PO7', Offset(0.33, 0.82)),
    ('Oz', Offset(0.50, 0.88)),
    ('PO8', Offset(0.67, 0.82)),
  ];

  static Color _heat(double v) {
    v = v.clamp(0.0, 1.0);
    if (v < 0.25) return Color.lerp(const Color(0xFF1A6EFA), const Color(0xFF00D4FF), v / 0.25)!;
    if (v < 0.50) return Color.lerp(const Color(0xFF00D4FF), const Color(0xFF00C896), (v - 0.25) / 0.25)!;
    if (v < 0.75) return Color.lerp(const Color(0xFF00C896), const Color(0xFFFFC400), (v - 0.50) / 0.25)!;
    return Color.lerp(const Color(0xFFFFC400), const Color(0xFFFF3B55), (v - 0.75) / 0.25)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final headR = min(w, h) * 0.42;
    final center = Offset(w / 2, h / 2);

    // ── head outline + nose + ears ──────────────────────────────────────────
    final outline = Paint()
      ..color = AppColors.inkBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, headR, outline);
    // nose (top)
    final nose = Path()
      ..moveTo(center.dx - headR * 0.12, center.dy - headR)
      ..lineTo(center.dx, center.dy - headR * 1.16)
      ..lineTo(center.dx + headR * 0.12, center.dy - headR);
    canvas.drawPath(nose, outline);
    // ears
    canvas.drawArc(
        Rect.fromCircle(center: Offset(center.dx - headR, center.dy), radius: headR * 0.18),
        pi * 0.5, pi, false, outline);
    canvas.drawArc(
        Rect.fromCircle(center: Offset(center.dx + headR, center.dy), radius: headR * 0.18),
        -pi * 0.5, pi, false, outline);

    // ── normalise channels ───────────────────────────────────────────────────
    final n = channels.length;
    double maxV = 0;
    for (final v in channels) {
      maxV = max(maxV, v);
    }
    final hasSignal = n > 0 && maxV > 0;

    Offset posFor(Offset norm) => Offset(
          center.dx + (norm.dx - 0.5) * headR * 2,
          center.dy + (norm.dy - 0.5) * headR * 2,
        );

    for (var i = 0; i < _layout.length; i++) {
      final (name, norm) = _layout[i];
      final p = posFor(norm);
      final v = (hasSignal && i < n) ? (channels[i] / maxV).clamp(0.0, 1.0) : 0.0;
      final color = hasSignal ? _heat(v) : AppColors.inkMuted;

      // pulse stronger where activity is higher
      final pulse = 1 + 0.18 * v * sin(phase * 2 * pi);
      final r = (headR * 0.10) * (0.7 + 0.7 * v) * pulse;

      // glow
      canvas.drawCircle(
          p,
          r * 2.0,
          Paint()
            ..shader = RadialGradient(colors: [
              color.withValues(alpha: 0.35 * (hasSignal ? 1 : 0.3)),
              color.withValues(alpha: 0.0),
            ]).createShader(Rect.fromCircle(center: p, radius: r * 2.0)));
      // core
      canvas.drawCircle(p, r, Paint()..color = color.withValues(alpha: hasSignal ? 0.9 : 0.4));
      canvas.drawCircle(
          p,
          r,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);

      // label
      final tp = TextPainter(
        text: TextSpan(
            text: name,
            style: GoogleFonts.schibstedGrotesk(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 10,
                fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p + Offset(-tp.width / 2, r + 2));
    }

    if (!hasSignal) {
      final tp = TextPainter(
        text: TextSpan(
            text: 'No EEG signal',
            style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center + Offset(-tp.width / 2, headR + 18));
    }
  }

  @override
  bool shouldRepaint(_HeadPainter old) =>
      old.phase != phase || !listEquals(old.channels, channels);
}

/// Local list compare (avoids importing foundation just for this).
bool listEquals(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
