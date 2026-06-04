import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

/// EEG panel — animated placeholder (Unity does not have EEG yet).
/// When EEG data is available from Unity, replace the demo waveform
/// generators with real data from UnityConnectionService.
class EEGPanel extends StatefulWidget {
  const EEGPanel({super.key});
  @override
  State<EEGPanel> createState() => _EEGPanelState();
}

class _EEGPanelState extends State<EEGPanel> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _rng = Random(42);
  final List<String> _channels = ['Fz', 'Cz', 'Pz', 'C3', 'C4', 'F3', 'F4', 'Oz'];

  final _bandPower = {
    'Theta (4–7 Hz)':  6.21,
    'Alpha (8–12 Hz)': 9.84,
    'Beta (13–30 Hz)': 4.37,
  };

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
    return DashboardPanel(
      title: 'EEG Monitoring',
      icon: Icons.psychology_outlined,
      iconColor: const Color(0xFFBB86FC),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Live EEG (8 Channels)', style: GoogleFonts.inter(
          color: AppColors.textSecondary, fontSize: 9,
        )),
        const SizedBox(width: 8),
        Text('Scale: 50 µV', style: GoogleFonts.inter(
          color: AppColors.textSecondary, fontSize: 9,
        )),
        const SizedBox(width: 8),
      ]),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          // Waveforms column
          Expanded(
            flex: 3,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Column(
                children: _channels.map((ch) => Expanded(
                  child: _WaveformRow(
                    label: ch,
                    phase: _ctrl.value * 2 * pi + _channels.indexOf(ch) * 0.7,
                    noiseAmp: 0.08 + _rng.nextDouble() * 0.04,
                  ),
                )).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Right column: topographic map + band power
          SizedBox(
            width: 90,
            child: Column(children: [
              const SizedBox(height: 4),
              SizedBox(
                width: 80, height: 80,
                child: CustomPaint(painter: _TopoMapPainter(_ctrl)),
              ),
              const SizedBox(height: 8),
              ..._bandPower.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _bandColor(e.key),
                  )),
                  const SizedBox(width: 4),
                  Expanded(child: Text(e.key.split(' ')[0],
                    style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 8))),
                  Text(e.value.toStringAsFixed(2),
                    style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 9,
                      fontWeight: FontWeight.w600)),
                ]),
              )),
              const Spacer(),
              _StatusRow('Signal Quality', true),
              const SizedBox(height: 4),
              _StatusRow('Artifact Level', false),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.accentOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.accentOrange.withOpacity(0.3)),
                ),
                child: Text('EEG sensor\nnot yet\nconnected',
                  style: GoogleFonts.inter(color: AppColors.accentOrange, fontSize: 8),
                  textAlign: TextAlign.center),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Color _bandColor(String band) {
    if (band.startsWith('Theta')) return Colors.blueAccent;
    if (band.startsWith('Alpha')) return AppColors.accentGreen;
    return AppColors.accentRed;
  }
}

class _WaveformRow extends StatelessWidget {
  final String label;
  final double phase;
  final double noiseAmp;

  const _WaveformRow({required this.label, required this.phase, required this.noiseAmp});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 20,
        child: Text(label, style: GoogleFonts.inter(
          color: AppColors.textSecondary, fontSize: 9,
        )),
      ),
      Expanded(
        child: CustomPaint(
          painter: _WaveformPainter(phase, noiseAmp),
          child: const SizedBox.expand(),
        ),
      ),
    ]);
  }
}

class _WaveformPainter extends CustomPainter {
  final double phase;
  final double noiseAmp;
  final _rng = Random(1234);

  _WaveformPainter(this.phase, this.noiseAmp);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A6EFA).withOpacity(0.8)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final path = Path();
    final midY  = size.height / 2;
    final ampY  = size.height * 0.35;
    const points = 120;

    for (int i = 0; i < points; i++) {
      final x = size.width * i / (points - 1);
      final t = phase + i * 0.25;
      final y = midY - ampY * (
        0.6 * sin(t) +
        0.25 * sin(t * 2.5 + 0.5) +
        0.15 * sin(t * 5.0 + 1.0) +
        noiseAmp * ((_rng.nextDouble() - 0.5) * 2)
      );
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }

    canvas.drawLine(Offset(0, midY), Offset(size.width, midY),
      Paint()..color = AppColors.border..strokeWidth = 0.3);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.phase != phase;
}

class _TopoMapPainter extends CustomPainter {
  final Animation<double> anim;
  _TopoMapPainter(this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final cx = size.width / 2, cy = size.height / 2;
    final r  = min(cx, cy) - 2;
    if (r <= 0) return;

    // Head outline
    canvas.drawCircle(Offset(cx, cy), r, Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    // Animated activity blobs
    final t = anim.value;
    final blobs = [
      (cx, cy - r * 0.5, 0.6 + 0.4 * sin(t * 2 * pi)),           // Fz
      (cx - r * 0.35, cy, 0.5 + 0.5 * sin(t * 2 * pi + 1.0)),    // C3
      (cx + r * 0.35, cy, 0.4 + 0.6 * sin(t * 2 * pi + 2.0)),    // C4
      (cx, cy + r * 0.3, 0.3 + 0.4 * sin(t * 2 * pi + 3.0)),     // Oz
    ];

    for (final (bx, by, intensity) in blobs) {
      final blobR = r * 0.3 * intensity;
      if (blobR <= 0) continue;
      canvas.drawCircle(
        Offset(bx, by), blobR,
        Paint()..shader = RadialGradient(
          colors: [
            const Color(0xFFBB86FC).withOpacity((0.6 * intensity).clamp(0.0, 1.0)),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: Offset(bx, by), radius: blobR)),
      );
    }

    // Electrode dots + labels
    final electrodes = [
      ('Fz', cx, cy - r * 0.5), ('Cz', cx, cy),
      ('Pz', cx, cy + r * 0.4),
      ('C3', cx - r * 0.5, cy), ('C4', cx + r * 0.5, cy),
      ('F3', cx - r * 0.3, cy - r * 0.4),
      ('F4', cx + r * 0.3, cy - r * 0.4),
      ('Oz', cx, cy + r * 0.8),
    ];

    for (final (label, ex, ey) in electrodes) {
      canvas.drawCircle(Offset(ex, ey), 3.5, Paint()
        ..color = AppColors.accentGreen);
      final tp = TextPainter(
        text: TextSpan(text: label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 7)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ex - tp.width / 2, ey - tp.height - 3));
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

class _StatusRow extends StatelessWidget {
  final String label;
  final bool good;
  const _StatusRow(this.label, this.good);

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(label,
      style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 8))),
    Container(width: 5, height: 5, decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: good ? AppColors.accentGreen : AppColors.accentOrange,
    )),
    const SizedBox(width: 3),
    Text(good ? 'Good' : 'Low',
      style: GoogleFonts.inter(
        color: good ? AppColors.accentGreen : AppColors.accentOrange,
        fontSize: 8,
      )),
  ]);
}
