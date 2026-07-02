import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../services/unity_connection_service.dart';
import '../../../theme/app_theme.dart';

class EEGPanel extends StatefulWidget {
  const EEGPanel({super.key});
  @override
  State<EEGPanel> createState() => _EEGPanelState();
}

class _EEGPanelState extends State<EEGPanel> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  // Per-channel EEG characteristics (dominant freq, amplitude, noise level)
  // Indexed to match [Fz, Cz, Pz, C3, C4, F3, F4, Oz]
  static const _channels = ['Fz', 'Cz', 'Pz', 'C3', 'C4', 'F3', 'F4', 'Oz'];

  static const _channelParams = [
    // (alphaAmp, betaAmp, thetaAmp, noise) — normalised 0..1
    (0.30, 0.55, 0.25, 0.10),  // Fz  — frontal: more beta
    (0.45, 0.40, 0.20, 0.08),  // Cz  — central: alpha + beta
    (0.55, 0.25, 0.20, 0.07),  // Pz  — parietal: alpha dominant
    (0.50, 0.35, 0.15, 0.09),  // C3  — motor left
    (0.48, 0.38, 0.15, 0.09),  // C4  — motor right
    (0.28, 0.58, 0.30, 0.12),  // F3  — frontal L: beta + theta
    (0.26, 0.56, 0.28, 0.11),  // F4  — frontal R
    (0.60, 0.20, 0.18, 0.06),  // Oz  — occipital: high alpha
  ];

  static const _bandPower = [
    ('Theta', '4–7 Hz',  6.21, Color(0xFF5B9BFF)),
    ('Alpha', '8–12 Hz', 9.84, Color(0xFF00C896)),
    ('Beta',  '13–30 Hz',4.37, Color(0xFFFF5B7A)),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final eeg = context.watch<UnityConnectionService>().state.eeg;

    // Band powers — real when the Unicorn streams, else the static placeholders.
    final bands = eeg != null
        ? [
            ('Theta', '4–7 Hz', eeg.theta, const Color(0xFF5B9BFF)),
            ('Alpha', '8–12 Hz', eeg.alpha, const Color(0xFF00C896)),
            ('Beta', '13–30 Hz', eeg.beta, const Color(0xFFFF5B7A)),
          ]
        : _bandPower;

    // Per-channel waveform amplitude from real RMS, normalised to the busiest channel.
    final ampScale = List<double>.filled(_channels.length, 1.0);
    if (eeg != null && eeg.channels.isNotEmpty) {
      final maxR = eeg.channels.reduce(max);
      for (var i = 0; i < _channels.length; i++) {
        final r = i < eeg.channels.length ? eeg.channels[i] : 0.0;
        ampScale[i] = maxR > 0 ? (0.2 + 0.8 * (r / maxR)).clamp(0.1, 1.0) : 1.0;
      }
    }

    final quality = eeg?.quality ?? 'Good';
    final artifact = eeg?.artifact ?? 'Low';
    final qColor = quality == 'Good'
        ? AppColors.accentGreen
        : (quality == 'Fair' ? AppColors.accentOrange : AppColors.accentRed);
    final aColor = artifact == 'Low' ? AppColors.accentGreen : AppColors.accentOrange;

    return DashboardPanel(
      title: 'EEG Monitoring',
      icon: Icons.psychology_outlined,
      iconColor: const Color(0xFFBB86FC),
      trailing: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Live EEG (8 Channels)', style: GoogleFonts.schibstedGrotesk(
            color: AppColors.inkMuted, fontSize: 9,
          )),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.inkSurfaceAlt,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.inkBorder),
            ),
            child: Text('Scale: 50 µV', style: GoogleFonts.schibstedGrotesk(
              color: AppColors.inkMuted, fontSize: 8.5,
            )),
          ),
        ]),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(children: [
          // ── Waveform column ──────────────────────────────────────────
          Expanded(
            flex: 3,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Column(
                children: List.generate(_channels.length, (i) => Expanded(
                  child: _WaveformRow(
                    label: _channels[i],
                    tick: _ctrl.value,
                    channelIndex: i,
                    params: _channelParams[i],
                    ampScale: ampScale[i],
                  ),
                )),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ── Right sidebar ────────────────────────────────────────────
          SizedBox(
            width: 94,
            child: Column(children: [
              // Topographic map
              SizedBox(
                width: 84, height: 84,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => CustomPaint(
                    painter: _TopoMapPainter(_ctrl),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Band power legend
              Text('Band Power (µV²)', style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkMuted, fontSize: 7.5,
              )),
              const SizedBox(height: 4),
              ...bands.map((b) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(
                    shape: BoxShape.circle, color: b.$4,
                  )),
                  const SizedBox(width: 4),
                  Expanded(child: Text(b.$1,
                    style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 8))),
                  Text(b.$3.toStringAsFixed(2), style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.inkText, fontSize: 9, fontWeight: FontWeight.w700)),
                ]),
              )),
              const Spacer(),
              // Status rows (live signal-quality flags from the connector)
              _StatusRow('Signal Quality', qColor, quality),
              const SizedBox(height: 3),
              _StatusRow('Artifact Level', aColor, artifact),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Per-channel EEG waveform row ─────────────────────────────────────────────
class _WaveformRow extends StatelessWidget {
  final String label;
  final double tick;         // 0..1 animation phase
  final int channelIndex;
  final (double, double, double, double) params; // alpha, beta, theta, noise amps
  final double ampScale;     // 0..1 live amplitude from real per-channel RMS

  const _WaveformRow({
    required this.label,
    required this.tick,
    required this.channelIndex,
    required this.params,
    this.ampScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 22,
        child: Text(label, style: GoogleFonts.schibstedGrotesk(
          color: AppColors.inkMuted, fontSize: 9, fontWeight: FontWeight.w500,
        )),
      ),
      Expanded(
        child: CustomPaint(
          painter: _EEGWaveformPainter(
            tick: tick,
            channelIndex: channelIndex,
            alphaAmp: params.$1,
            betaAmp:  params.$2,
            thetaAmp: params.$3,
            noiseAmp: params.$4,
            ampScale: ampScale,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ]);
  }
}

class _EEGWaveformPainter extends CustomPainter {
  final double tick;
  final int channelIndex;
  final double alphaAmp, betaAmp, thetaAmp, noiseAmp;
  final double ampScale; // scales the drawn trace by the channel's live RMS
  // Per-channel pseudo-random noise seed
  late final Random _rng;

  _EEGWaveformPainter({
    required this.tick,
    required this.channelIndex,
    required this.alphaAmp,
    required this.betaAmp,
    required this.thetaAmp,
    required this.noiseAmp,
    this.ampScale = 1.0,
  }) {
    _rng = Random(channelIndex * 137 + 42);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final midY = size.height / 2;
    final ampY = size.height * 0.38 * ampScale;
    const pts  = 150;
    final phase = tick * 2 * pi + channelIndex * 0.9;

    final path = Path();
    for (int i = 0; i < pts; i++) {
      final x = size.width * i / (pts - 1);
      final t = phase + i * 0.18;
      // EEG = weighted sum of alpha (10Hz), beta (20Hz), theta (6Hz) bands
      // plus small Gaussian-ish noise
      final signal = ampY * (
        alphaAmp * sin(t * 2.5)                             // alpha ~10 Hz
        + betaAmp  * sin(t * 5.0 + 0.7)                    // beta  ~20 Hz
        + thetaAmp * sin(t * 1.5 + 1.2)                    // theta ~6 Hz
        + betaAmp  * 0.3 * sin(t * 7.5 + 2.1)              // high beta
        + noiseAmp * (_rng.nextDouble() * 2 - 1)            // broadband noise
      );
      final y = midY - signal;
      if (i == 0) path.moveTo(x, y.clamp(0, size.height));
      else        path.lineTo(x, y.clamp(0, size.height));
    }

    // Baseline
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY),
      Paint()..color = AppColors.inkBorder..strokeWidth = 0.4);

    // Waveform
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF1A6EFA).withValues(alpha: 0.85)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_EEGWaveformPainter old) =>
      old.tick != tick || old.ampScale != ampScale;
}

// ── Topographic head map ──────────────────────────────────────────────────────
class _TopoMapPainter extends CustomPainter {
  final Animation<double> anim;
  _TopoMapPainter(this.anim) : super(repaint: anim);

  static const _electrodes = [
    ('Fz',  0.50, 0.22),
    ('Cz',  0.50, 0.50),
    ('Pz',  0.50, 0.78),
    ('C3',  0.22, 0.50),
    ('C4',  0.78, 0.50),
    ('F3',  0.28, 0.28),
    ('F4',  0.72, 0.28),
    ('Oz',  0.50, 0.92),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = min(cx, cy) - 4;
    if (r <= 2) return;
    final t  = anim.value;

    // Head circle
    canvas.drawCircle(Offset(cx, cy), r, Paint()
      ..color = AppColors.inkSurfaceAlt
      ..style = PaintingStyle.fill);
    canvas.drawCircle(Offset(cx, cy), r, Paint()
      ..color = AppColors.inkBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    // Nose indicator
    canvas.drawLine(
      Offset(cx - 4, cy - r + 1),
      Offset(cx,     cy - r - 5),
      Paint()..color = AppColors.inkBorder..strokeWidth = 1.5..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(cx, cy - r - 5),
      Offset(cx + 4, cy - r + 1),
      Paint()..color = AppColors.inkBorder..strokeWidth = 1.5..strokeCap = StrokeCap.round,
    );

    // Animated activity blobs at motor/visual cortex areas
    final blobs = [
      (cx + (0.50 - 0.50) * r * 2, cy + (0.22 - 0.50) * r * 2,
        0.4 + 0.35 * sin(t * 2 * pi),         const Color(0xFFBB86FC)), // Fz
      (cx + (0.22 - 0.50) * r * 2, cy + (0.50 - 0.50) * r * 2,
        0.5 + 0.45 * sin(t * 2 * pi + 1.2),   const Color(0xFF1A6EFA)), // C3
      (cx + (0.78 - 0.50) * r * 2, cy + (0.50 - 0.50) * r * 2,
        0.4 + 0.40 * sin(t * 2 * pi + 2.1),   const Color(0xFF1A6EFA)), // C4
      (cx + (0.50 - 0.50) * r * 2, cy + (0.78 - 0.50) * r * 2,
        0.3 + 0.30 * sin(t * 2 * pi + 3.0),   const Color(0xFF00C896)), // Oz
    ];
    for (final b in blobs) {
      final blobR = r * 0.45 * b.$3;
      if (blobR <= 0) continue;
      canvas.drawCircle(
        Offset(b.$1, b.$2), blobR,
        Paint()..shader = RadialGradient(
          colors: [
            b.$4.withValues(alpha: (0.5 * b.$3).clamp(0.0, 0.7)),
            b.$4.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(b.$1, b.$2), radius: blobR)),
      );
    }

    // Electrode dots + labels
    for (final e in _electrodes) {
      final ex = cx + (e.$2 - 0.50) * r * 2;
      final ey = cy + (e.$3 - 0.50) * r * 2;
      // Check inside head
      if ((ex - cx) * (ex - cx) + (ey - cy) * (ey - cy) > (r + 4) * (r + 4)) continue;
      canvas.drawCircle(Offset(ex, ey), 3.5, Paint()..color = AppColors.accentGreen);
      canvas.drawCircle(Offset(ex, ey), 3.5, Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8);
      final tp = TextPainter(
        text: TextSpan(text: e.$1,
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 6.5)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ex - tp.width / 2, ey - tp.height - 3));
    }
  }

  @override bool shouldRepaint(_) => true;
}

// ── Status row ────────────────────────────────────────────────────────────────
class _StatusRow extends StatelessWidget {
  final String label;
  final Color color;
  final String status;
  const _StatusRow(this.label, this.color, this.status);

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(label, style: GoogleFonts.schibstedGrotesk(
      color: AppColors.inkMuted, fontSize: 8,
    ))),
    Container(width: 5, height: 5, decoration: BoxDecoration(
      shape: BoxShape.circle, color: color,
    )),
    const SizedBox(width: 3),
    Text(status, style: GoogleFonts.schibstedGrotesk(color: color, fontSize: 8)),
  ]);
}
