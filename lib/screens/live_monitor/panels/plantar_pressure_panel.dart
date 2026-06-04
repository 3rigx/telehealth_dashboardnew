import 'dart:math';
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

    return DashboardPanel(
      title: 'Plantar Pressure',
      icon: Icons.accessibility,
      iconColor: AppColors.accentCyan,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          // Foot heatmaps row
          Expanded(
            flex: 5,
            child: Row(children: [
              Expanded(child: _FootHeatmap(label: 'Left Foot', values: p.leftFoot)),
              const SizedBox(width: 8),
              Expanded(child: _FootHeatmap(label: 'Right Foot', values: p.rightFoot)),
              const SizedBox(width: 8),
              _PressureLegend(),
            ]),
          ),
          const SizedBox(height: 8),
          // Time chart
          Expanded(
            flex: 3,
            child: _PressureTimeChart(history: state.pressureHistory),
          ),
          const SizedBox(height: 8),
          // Metrics
          _MetricsGrid(p: p),
        ]),
      ),
    );
  }
}

// ── Foot heatmap ─────────────────────────────────────────────────────────────
class _FootHeatmap extends StatelessWidget {
  final String label;
  final List<double> values; // 16 sensor values

  const _FootHeatmap({required this.label, required this.values});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label, style: GoogleFonts.inter(
        color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w500,
      )),
      const SizedBox(height: 4),
      Expanded(child: CustomPaint(
        painter: _FootPainter(values.isEmpty ? List.filled(16, 0.0) : values),
        child: const SizedBox.expand(),
      )),
    ]);
  }
}

class _FootPainter extends CustomPainter {
  final List<double> values;
  _FootPainter(this.values);

  static Color _heatColor(double v) {
    v = v.clamp(0.0, 1.0);
    if (v < 0.25) return Color.lerp(const Color(0xFF0000FF), const Color(0xFF00AAFF), v / 0.25)!;
    if (v < 0.50) return Color.lerp(const Color(0xFF00AAFF), const Color(0xFF00FFAA), (v - 0.25) / 0.25)!;
    if (v < 0.75) return Color.lerp(const Color(0xFF00FFAA), const Color(0xFFFFAA00), (v - 0.50) / 0.25)!;
    return Color.lerp(const Color(0xFFFFAA00), const Color(0xFFFF0000), (v - 0.75) / 0.25)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const cols = 4, rows = 4;
    final cw = size.width / cols;
    final ch = size.height / rows;

    // Foot outline
    final footPath = Path();
    footPath.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.05, 0, size.width * 0.9, size.height),
      Radius.circular(size.width * 0.3),
    ));
    canvas.save();
    canvas.clipPath(footPath);

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final idx = row * cols + col;
        final val = idx < values.length ? values[idx] : 0.0;
        final paint = Paint()..color = _heatColor(val).withOpacity(0.85 + val * 0.15);
        final rect  = Rect.fromLTWH(col * cw, row * ch, cw, ch);
        canvas.drawRect(rect, paint);

        // Sensor number
        final tp = TextPainter(
          text: TextSpan(
            text: '${idx + 1}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5), fontSize: cw * 0.22,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
      }
    }
    canvas.restore();

    // Outline
    canvas.drawPath(footPath, Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_FootPainter old) => true;
}

// ── Pressure legend ──────────────────────────────────────────────────────────
class _PressureLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Pressure\nIntensity', style: GoogleFonts.inter(
          color: AppColors.textSecondary, fontSize: 8,
        ), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        SizedBox(
          width: 12, height: 80,
          child: CustomPaint(painter: _GradientBarPainter()),
        ),
        const SizedBox(height: 4),
        Text('High', style: GoogleFonts.inter(color: AppColors.accentRed, fontSize: 8)),
        const Spacer(),
        Text('Low', style: GoogleFonts.inter(color: const Color(0xFF0000FF), fontSize: 8)),
      ],
    );
  }
}

class _GradientBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFF0000), Color(0xFFFFAA00), Color(0xFF00FFAA), Color(0xFF0000FF)],
    ).createShader(rect));
  }
  @override bool shouldRepaint(_) => false;
}

// ── Pressure time chart ──────────────────────────────────────────────────────
class _PressureTimeChart extends StatelessWidget {
  final List<double> history;
  const _PressureTimeChart({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) return const SizedBox();

    final spots = history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pressure Over Time (Total Load)',
          style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 9)),
        const SizedBox(height: 4),
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.border, strokeWidth: 0.5,
                ),
                getDrawingVerticalLine: (_) => FlLine(
                  color: AppColors.border.withOpacity(0.3), strokeWidth: 0.3,
                ),
              ),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 28,
                  getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 8)),
                )),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 16,
                  getTitlesWidget: (v, _) {
                    final t = -(history.length - 1 - v.toInt());
                    return Text('${t}s', style: GoogleFonts.inter(
                      color: AppColors.textSecondary, fontSize: 8));
                  },
                )),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: AppColors.accentCyan,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.accentCyan.withOpacity(0.08),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Metrics grid ─────────────────────────────────────────────────────────────
class _MetricsGrid extends StatelessWidget {
  final PlantarData p;
  const _MetricsGrid({required this.p});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Total Load',          '${p.totalLoad.toStringAsFixed(1)} %BW'),
      ('Heel Load',           '${p.heelLoad.toStringAsFixed(1)} %BW'),
      ('Forefoot Load',       '${p.forefootLoad.toStringAsFixed(1)} %BW'),
      ('L/R Asymmetry',       '${p.asymmetry.toStringAsFixed(1)} %'),
      ('Stability (COP SD)',  '${p.stability.toStringAsFixed(2)} cm'),
    ];

    return Column(
      children: rows.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Text(r.$1, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 10)),
          const Spacer(),
          Text(r.$2, style: GoogleFonts.inter(
            color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w600,
          )),
          const SizedBox(width: 4),
          _StatusDot(r.$1, r.$2, p),
        ]),
      )).toList(),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String label;
  final String value;
  final PlantarData p;
  const _StatusDot(this.label, this.value, this.p);

  @override
  Widget build(BuildContext context) {
    bool good = true;
    if (label == 'L/R Asymmetry') good = p.asymmetry < 15;
    if (label == 'Stability (COP SD)') good = p.stability < 1.0;
    return Container(
      width: 6, height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: good ? AppColors.accentGreen : AppColors.accentOrange,
      ),
    );
  }
}
