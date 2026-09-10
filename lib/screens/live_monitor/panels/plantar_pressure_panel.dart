import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../services/unity_connection_service.dart';
import '../../../models/telerehab_state.dart';
import '../../../theme/app_theme.dart';

class PlantarPressurePanel extends StatelessWidget {
  const PlantarPressurePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<UnityConnectionService>().state;
    final p = state.plantar;
    final footLabel = p.foot.isEmpty
        ? 'Foot'
        : '${p.foot[0].toUpperCase()}${p.foot.substring(1)} Foot';

    return DashboardPanel(
      title: 'Plantar Pressure',
      icon: Icons.accessibility,
      iconColor: AppColors.accentCyan,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          if (p.baselineUnderLoad) ...[
            const _BaselineWarning(),
            const SizedBox(height: 6),
          ],
          // ── Single foot zone map + legend ──────────────────────────
          Expanded(
            flex: 5,
            child: Row(children: [
              const Spacer(),
              Expanded(flex: 3, child: _FootZonesView(label: footLabel, zones: p.zones, isLeft: p.isLeft)),
              const SizedBox(width: 8),
              _PressureLegend(),
              const Spacer(),
            ]),
          ),
          const SizedBox(height: 6),
          // ── Bottom: total-load chart + metrics side by side ────────
          Expanded(
            flex: 4,
            child: Row(children: [
              Expanded(
                flex: 3,
                child: _PressureTimeChart(history: state.pressureHistory),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 152, child: _MetricsColumn(p: p)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Baseline-under-load warning banner ───────────────────────────────────────
class _BaselineWarning extends StatelessWidget {
  const _BaselineWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.accentRed.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: AppColors.accentRed, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Baseline captured under load. Remove foot and re-baseline.',
            style: GoogleFonts.schibstedGrotesk(
              color: AppColors.accentRed, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}

// ── Four-zone anatomical foot view ───────────────────────────────────────────
class _FootZonesView extends StatelessWidget {
  final String label;
  final FootZones zones;
  final bool isLeft;

  const _FootZonesView({required this.label, required this.zones, required this.isLeft});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label, style: GoogleFonts.schibstedGrotesk(
        color: AppColors.inkMuted, fontSize: 10, fontWeight: FontWeight.w500,
      )),
      const SizedBox(height: 4),
      Expanded(child: CustomPaint(
        painter: _FootZonesPainter(zones: zones, isLeft: isLeft),
        child: const SizedBox.expand(),
      )),
    ]);
  }
}

class _FootZonesPainter extends CustomPainter {
  final FootZones zones;
  final bool isLeft;
  _FootZonesPainter({required this.zones, required this.isLeft});

  static Color _heat(double v) {
    v = v.clamp(0.0, 1.0);
    if (v < 0.20) return Color.lerp(const Color(0xFF0033CC), const Color(0xFF0099FF), v / 0.20)!;
    if (v < 0.40) return Color.lerp(const Color(0xFF0099FF), const Color(0xFF00DDAA), (v-0.20)/0.20)!;
    if (v < 0.60) return Color.lerp(const Color(0xFF00DDAA), const Color(0xFFAAFF00), (v-0.40)/0.20)!;
    if (v < 0.80) return Color.lerp(const Color(0xFFAAFF00), const Color(0xFFFFAA00), (v-0.60)/0.20)!;
    return           Color.lerp(const Color(0xFFFFAA00), const Color(0xFFFF1100), (v-0.80)/0.20)!;
  }

  // Normalised zone centres (x medial/lateral resolved by foot side, y toe→heel).
  Offset _toe()     => const Offset(0.50, 0.13);
  Offset _heel()    => const Offset(0.50, 0.85);
  Offset _medial()  => Offset(isLeft ? 0.66 : 0.34, 0.48);
  Offset _lateral() => Offset(isLeft ? 0.34 : 0.66, 0.48);

  Path _footOutline(double w, double h) {
    final medX = isLeft ? w * 0.85 : w * 0.15;
    final latX = isLeft ? w * 0.15 : w * 0.85;
    final path = Path();
    path.moveTo(latX, h * 0.02);
    path.quadraticBezierTo(w * 0.50, h * -0.04, medX, h * 0.02);
    path.cubicTo(
      medX + (isLeft ? -w*0.05 : w*0.05), h * 0.30,
      medX + (isLeft ? -w*0.20 : w*0.20), h * 0.52,
      medX + (isLeft ? -w*0.10 : w*0.10), h * 0.72,
    );
    path.quadraticBezierTo(medX, h * 0.90, w * 0.50, h * 0.98);
    path.quadraticBezierTo(latX, h * 0.90, latX + (isLeft ? w*0.05 : -w*0.05), h * 0.70);
    path.cubicTo(latX, h * 0.55, latX, h * 0.30, latX, h * 0.02);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final footPath = _footOutline(w, h);

    canvas.save();
    canvas.clipPath(footPath);
    canvas.drawRect(Offset.zero & size,
        Paint()..color = const Color(0xFF0033CC).withValues(alpha: 0.22));

    final blobs = <(Offset, double, String)>[
      (_toe(),     zones.toe,     'Toe'),
      (_medial(),  zones.medial,  'Medial'),
      (_lateral(), zones.lateral, 'Lateral'),
      (_heel(),    zones.heel,    'Heel'),
    ];

    for (final (pos, v, _) in blobs) {
      if (v <= 0.02) continue;
      final c = Offset(pos.dx * w, pos.dy * h);
      final r = w * 0.42 * (0.55 + v * 0.6);
      canvas.drawCircle(c, r, Paint()
        ..shader = RadialGradient(colors: [
          _heat(v).withValues(alpha: (0.75 * v + 0.2).clamp(0.0, 0.9)),
          _heat(v).withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }

    // Zone labels + values
    for (final (pos, v, name) in blobs) {
      final c = Offset(pos.dx * w, pos.dy * h);
      _text(canvas, name, c.translate(0, -7), 8.5, Colors.white.withValues(alpha: 0.65));
      _text(canvas, '${(v * 100).round()}', c.translate(0, 4), 11,
          Colors.white.withValues(alpha: 0.95), bold: true);
    }

    // Center-of-pressure marker (weighted centroid of the four zones)
    final total = zones.sum;
    if (total > 0.04) {
      double cx = 0, cy = 0;
      for (final (pos, v, _) in blobs) { cx += pos.dx * v; cy += pos.dy * v; }
      final cop = Offset(cx / total * w, cy / total * h);
      canvas.drawCircle(cop, 7, Paint()
        ..color = Colors.white.withValues(alpha: 0.25));
      canvas.drawCircle(cop, 4, Paint()..color = Colors.white);
      canvas.drawCircle(cop, 4, Paint()
        ..color = AppColors.accentRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6);
    }
    canvas.restore();

    canvas.drawPath(footPath, Paint()
      ..color = AppColors.inkBorder.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  void _text(Canvas c, String s, Offset center, double size, Color color, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: GoogleFonts.schibstedGrotesk(
        color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_FootZonesPainter old) =>
      old.zones != zones || old.isLeft != isLeft;
}

// ── Pressure legend ───────────────────────────────────────────────────────────
class _PressureLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Pressure\nIntensity', style: GoogleFonts.schibstedGrotesk(
          color: AppColors.inkMuted, fontSize: 8,
        ), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Row(children: [
          SizedBox(width: 10, height: 90, child: CustomPaint(painter: _GradientBarPainter())),
          const SizedBox(width: 2),
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('High', style: GoogleFonts.schibstedGrotesk(color: const Color(0xFFFF1100), fontSize: 7)),
              const SizedBox(height: 60),
              Text('Low',  style: GoogleFonts.schibstedGrotesk(color: const Color(0xFF0033CC), fontSize: 7)),
            ],
          ),
        ]),
      ],
    );
  }
}

class _GradientBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFF1100), Color(0xFFFFAA00), Color(0xFFAAFF00),
          Color(0xFF00DDAA), Color(0xFF0099FF), Color(0xFF0033CC),
        ],
      ).createShader(rect),
    );
  }
  @override bool shouldRepaint(_) => false;
}

// ── Pressure time chart — single total-load line ─────────────────────────────
class _PressureTimeChart extends StatelessWidget {
  final List<double> history;
  const _PressureTimeChart({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) return const SizedBox();

    final spots = <FlSpot>[
      for (int i = 0; i < history.length; i++) FlSpot(i.toDouble(), history[i]),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Pressure Over Time (Total Load)', style: GoogleFonts.schibstedGrotesk(
            color: AppColors.inkMuted, fontSize: 8.5,
          )),
          const SizedBox(width: 8),
          _LegendDot(AppColors.accentCyan, 'Total load'),
        ]),
        const SizedBox(height: 4),
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: AppColors.inkBorder, strokeWidth: 0.5),
              ),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  axisNameWidget: Text('% load', style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.inkMuted, fontSize: 7,
                  )),
                  axisNameSize: 28,
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 26, interval: 25,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}',
                      style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 7.5)),
                  ),
                ),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 14,
                  getTitlesWidget: (v, _) {
                    final t = -(history.length - 1 - v.toInt());
                    if (t % 2 != 0) return const SizedBox();
                    return Text('${t}s', style: GoogleFonts.schibstedGrotesk(
                      color: AppColors.inkMuted, fontSize: 7.5));
                  },
                )),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(bottom: BorderSide(color: AppColors.inkBorder)),
              ),
              minY: 0, maxY: 100,
              lineBarsData: [
                LineChartBarData(
                  spots: spots, isCurved: true, curveSmoothness: 0.35,
                  color: AppColors.accentCyan, barWidth: 1.8,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: AppColors.accentCyan.withValues(alpha: 0.08)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot(this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 20, height: 2, decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(1),
    )),
    const SizedBox(width: 3),
    Text(label, style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 7.5)),
  ]);
}

// ── Pressure metrics column ───────────────────────────────────────────────────
class _MetricsColumn extends StatelessWidget {
  final PlantarData p;
  const _MetricsColumn({required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.inkSurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.inkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pressure Metrics', style: GoogleFonts.schibstedGrotesk(
            color: AppColors.inkMuted, fontSize: 9, fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 6),
          ..._rows(p).map((r) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(children: [
              Expanded(child: Text(r.$1, style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkMuted, fontSize: 9,
              ))),
              Text(r.$2, style: GoogleFonts.schibstedGrotesk(
                color: r.$3 ?? AppColors.inkText,
                fontSize: 9.5, fontWeight: FontWeight.w700,
              )),
              if (r.$4 != null) ...[
                const SizedBox(width: 4),
                Container(width: 6, height: 6, decoration: BoxDecoration(
                  shape: BoxShape.circle, color: r.$4,
                )),
              ],
            ]),
          )),
        ],
      ),
    );
  }

  List<(String, String, Color?, Color?)> _rows(PlantarData p) => [
    ('Total Load',        '${p.totalLoad.toStringAsFixed(1)} %',    null, null),
    ('Heel Load',         '${p.heelLoad.toStringAsFixed(1)} %',     null, null),
    ('Forefoot Load',     '${p.forefootLoad.toStringAsFixed(1)} %', null, null),
    ('Stability (COP)',
      '${p.stability.toStringAsFixed(2)} cm',
      p.stability < 1.0 ? AppColors.accentGreen : AppColors.accentOrange,
      p.stability < 1.0 ? AppColors.accentGreen : AppColors.accentOrange,
    ),
  ];
}
