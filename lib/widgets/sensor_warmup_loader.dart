import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Full-area "warming up sensors" loader shown while Unity initialises the ZED
/// (and other sensors) before the first real frame. Pure Flutter animation — if
/// a `.riv` asset is later added, swap the [_PulsePainter] for a `RiveAnimation`.
class SensorWarmupLoader extends StatefulWidget {
  final String title;
  final String? message;
  const SensorWarmupLoader({super.key, this.title = 'Warming up sensors', this.message});

  @override
  State<SensorWarmupLoader> createState() => _SensorWarmupLoaderState();
}

class _SensorWarmupLoaderState extends State<SensorWarmupLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _timer;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
          width: 150,
          height: 150,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => CustomPaint(
                size: const Size(150, 150),
                painter: _PulsePainter(_pulse.value, AppColors.accent),
              ),
            ),
            const Icon(Icons.sensors, size: 40, color: AppColors.accent),
          ]),
        ),
        const SizedBox(height: 22),
        Text(widget.title,
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkText, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            widget.message ?? 'Getting the camera and sensors ready…',
            textAlign: TextAlign.center,
            style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 14),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: AppColors.inkSurfaceAlt,
              valueColor: AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('Elapsed ${_elapsed}s  ·  the ZED camera can take up to ~20 s',
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkMuted.withValues(alpha: 0.7), fontSize: 11)),
      ]).animate().fadeIn(duration: 300.ms),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double t; // 0..1 pulse phase
  final Color color;
  _PulsePainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide / 2;

    // Three expanding, fading rings, phase-offset for a continuous ripple.
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final r = maxR * (0.3 + 0.7 * p);
      final alpha = (1 - p) * 0.45;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // soft core
    canvas.drawCircle(c, maxR * 0.30, Paint()..color = color.withValues(alpha: 0.16));
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t || old.color != color;
}
