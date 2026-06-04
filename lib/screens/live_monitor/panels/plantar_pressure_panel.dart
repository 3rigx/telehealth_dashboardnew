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
          // ── Foot heatmaps + legend ─────────────────────────────────
          Expanded(
            flex: 5,
            child: Row(children: [
              Expanded(child: _FootHeatmap(
                label: 'Left Foot',
                values: p.leftFoot.isEmpty ? List.filled(16, 0.0) : p.leftFoot,
                isLeft: true,
              )),
              const SizedBox(width: 6),
              Expanded(child: _FootHeatmap(
                label: 'Right Foot',
                values: p.rightFoot.isEmpty ? List.filled(16, 0.0) : p.rightFoot,
                isLeft: false,
              )),
              const SizedBox(width: 6),
              _PressureLegend(),
            ]),
          ),
          const SizedBox(height: 6),
          // ── Bottom: chart + metrics side by side ───────────────────
          Expanded(
            flex: 4,
            child: Row(children: [
              // Pressure-over-time chart
              Expanded(
                flex: 3,
                child: _PressureTimeChart(
                  history: state.pressureHistory,
                  asymmetry: p.asymmetry,
                ),
              ),
              const SizedBox(width: 10),
              // Metrics column
              SizedBox(
                width: 148,
                child: _MetricsColumn(p: p),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Anatomical foot heatmap ───────────────────────────────────────────────────
class _FootHeatmap extends StatelessWidget {
  final String label;
  final List<double> values; // 16 sensor values 0..1
  final bool isLeft;

  const _FootHeatmap({
    required this.label,
    required this.values,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label, style: GoogleFonts.inter(
        color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w500,
      )),
      const SizedBox(height: 4),
      Expanded(child: CustomPaint(
        painter: _FootPainter(
          values: values.length == 16 ? values : List.filled(16, 0.0),
          isLeft: isLeft,
        ),
        child: const SizedBox.expand(),
      )),
    ]);
  }
}

// Sensor layout — 16 sensors mapped to normalised (x, y) positions
// on a plantar insole where (0,0) = top-left of bounding box,
// (1,1) = bottom-right.  X increases lateral→medial, Y increases toe→heel.
List<Offset> _sensorPositions(bool isLeft) {
  // Standard 4-column, 5-row-ish insole layout (viewed plantar/from below)
  // Column order (x): 0.15, 0.38, 0.62, 0.85
  // The foot is mirrored for right foot (flip x: x' = 1 - x)
  const raw = [
    // Row 0 — toes (y=0.08)
    Offset(0.18, 0.08), Offset(0.40, 0.08), Offset(0.62, 0.08), Offset(0.82, 0.08),
    // Row 1 — ball (y=0.25)
    Offset(0.15, 0.26), Offset(0.40, 0.26), Offset(0.62, 0.26), Offset(0.82, 0.26),
    // Row 2 — mid-foot (y=0.45)
    Offset(0.15, 0.46), Offset(0.40, 0.46), Offset(0.62, 0.46), Offset(0.80, 0.46),
    // Row 3 — arch/lower-mid (y=0.64)
    Offset(0.16, 0.65), Offset(0.42, 0.65), Offset(0.64, 0.65), Offset(0.80, 0.65),
    // Row 4 — heel (y=0.83) — only two central sensors
    // We treat sensors 15 & 16 as being at heel
  ];
  // Remap: sensors 1-14 = raw[0..13], sensors 15-16 at heel
  // But we only have 16 sensors total, so heel gets indices 14 & 15:
  const heel = [Offset(0.35, 0.84), Offset(0.65, 0.84)];
  final positions = [...raw.take(14), ...heel];
  if (isLeft) return positions;
  // Mirror for right foot
  return positions.map((p) => Offset(1.0 - p.dx, p.dy)).toList();
}

class _FootPainter extends CustomPainter {
  final List<double> values;
  final bool isLeft;
  _FootPainter({required this.values, required this.isLeft});

  static Color _heat(double v) {
    v = v.clamp(0.0, 1.0);
    if (v < 0.20) return Color.lerp(const Color(0xFF0033CC), const Color(0xFF0099FF), v / 0.20)!;
    if (v < 0.40) return Color.lerp(const Color(0xFF0099FF), const Color(0xFF00DDAA), (v-0.20)/0.20)!;
    if (v < 0.60) return Color.lerp(const Color(0xFF00DDAA), const Color(0xFFAAFF00), (v-0.40)/0.20)!;
    if (v < 0.80) return Color.lerp(const Color(0xFFAAFF00), const Color(0xFFFFAA00), (v-0.60)/0.20)!;
    return           Color.lerp(const Color(0xFFFFAA00), const Color(0xFFFF1100), (v-0.80)/0.20)!;
  }

  // Builds an anatomical foot outline path (plantar view)
  // Coords are in normalised [0,1]×[0,1] — caller must transform.
  Path _footOutline(double w, double h) {
    // The foot shape: rounded rectangle with arch cutout on one side
    // For left foot: arch is on the right side (lateral = left, medial = right)
    final medX = isLeft ? w * 0.85 : w * 0.15; // medial side x
    final latX = isLeft ? w * 0.15 : w * 0.85; // lateral side x

    final path = Path();
    // Start at top-lateral (near little toe)
    path.moveTo(latX, h * 0.02);
    // Toe region — rounded top
    path.quadraticBezierTo(w * 0.50, h * -0.04, medX, h * 0.02);
    // Medial side going down, with mild arch bulge inward
    path.cubicTo(
      medX + (isLeft ? -w*0.05 : w*0.05), h * 0.30,
      medX + (isLeft ? -w*0.20 : w*0.20), h * 0.52,  // arch narrows here
      medX + (isLeft ? -w*0.10 : w*0.10), h * 0.72,
    );
    // Heel - medial side
    path.quadraticBezierTo(medX, h * 0.90, w * 0.50, h * 0.98);
    // Heel - lateral side
    path.quadraticBezierTo(latX, h * 0.90, latX + (isLeft ? w*0.05 : -w*0.05), h * 0.70);
    // Lateral side going up
    path.cubicTo(
      latX, h * 0.55,
      latX, h * 0.30,
      latX, h * 0.02,
    );
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;

    final footPath = _footOutline(w, h);

    // Clip to foot shape
    canvas.save();
    canvas.clipPath(footPath);

    // Fill background (no-pressure colour)
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0033CC).withValues(alpha: 0.25));

    // Draw Gaussian-blended heat blobs for each sensor
    final positions = _sensorPositions(isLeft);
    for (int i = 0; i < min(positions.length, values.length); i++) {
      final p   = positions[i];
      final v   = values[i];
      if (v <= 0.02) continue;
      final cx  = p.dx * w;
      final cy  = p.dy * h;
      final r   = w * 0.28 * (0.6 + v * 0.7);
      final col = _heat(v);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..shader = RadialGradient(
          colors: [
            col.withValues(alpha: (0.7 * v + 0.2).clamp(0.0, 0.85)),
            col.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }

    // Draw sensor number labels
    for (int i = 0; i < min(positions.length, 16); i++) {
      final p  = positions[i];
      final cx = p.dx * w;
      final cy = p.dy * h;
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: (w * 0.11).clamp(7.0, 12.0),
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    }

    canvas.restore();

    // Foot outline border
    canvas.drawPath(footPath, Paint()
      ..color = AppColors.border.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(_FootPainter old) =>
      old.values != values || old.isLeft != isLeft;
}

// ── Pressure legend ───────────────────────────────────────────────────────────
class _PressureLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Pressure\nIntensity', style: GoogleFonts.inter(
          color: AppColors.textSecondary, fontSize: 8,
        ), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Row(children: [
          SizedBox(
            width: 10, height: 90,
            child: CustomPaint(painter: _GradientBarPainter()),
          ),
          const SizedBox(width: 2),
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('High', style: GoogleFonts.inter(color: const Color(0xFFFF1100), fontSize: 7)),
              const SizedBox(height: 60),
              Text('Low',  style: GoogleFonts.inter(color: const Color(0xFF0033CC), fontSize: 7)),
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
          Color(0xFFFF1100),
          Color(0xFFFFAA00),
          Color(0xFFAAFF00),
          Color(0xFF00DDAA),
          Color(0xFF0099FF),
          Color(0xFF0033CC),
        ],
      ).createShader(rect),
    );
  }
  @override bool shouldRepaint(_) => false;
}

// ── Pressure time chart — two lines (left + right) ───────────────────────────
class _PressureTimeChart extends StatelessWidget {
  final List<double> history;
  final double asymmetry; // % asymmetry to split total into L/R
  const _PressureTimeChart({required this.history, required this.asymmetry});

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) return const SizedBox();

    // Derive left/right from total + asymmetry
    final leftSpots = <FlSpot>[];
    final rightSpots = <FlSpot>[];
    for (int i = 0; i < history.length; i++) {
      final total = history[i];
      final ratio = (asymmetry / 200).clamp(-0.4, 0.4);
      leftSpots.add(FlSpot(i.toDouble(), total * (0.5 - ratio)));
      rightSpots.add(FlSpot(i.toDouble(), total * (0.5 + ratio)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Pressure Over Time (Total Load)', style: GoogleFonts.inter(
            color: AppColors.textSecondary, fontSize: 8.5,
          )),
          const SizedBox(width: 8),
          _LegendDot(AppColors.accentCyan, '← Left'),
          const SizedBox(width: 6),
          _LegendDot(AppColors.accentOrange, 'Right →'),
        ]),
        const SizedBox(height: 4),
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.border, strokeWidth: 0.5,
                ),
              ),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  axisNameWidget: Text('% Body\nWeight', style: GoogleFonts.inter(
                    color: AppColors.textSecondary, fontSize: 7,
                  )),
                  axisNameSize: 28,
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 26,
                    interval: 25,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}',
                      style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 7.5)),
                  ),
                ),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 14,
                  getTitlesWidget: (v, _) {
                    final t = -(history.length - 1 - v.toInt());
                    if (t % 2 != 0) return const SizedBox();
                    return Text('${t}s', style: GoogleFonts.inter(
                      color: AppColors.textSecondary, fontSize: 7.5));
                  },
                )),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              minY: 0, maxY: 100,
              lineBarsData: [
                LineChartBarData(
                  spots: leftSpots,
                  isCurved: true, curveSmoothness: 0.35,
                  color: AppColors.accentCyan,
                  barWidth: 1.8,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.accentCyan.withValues(alpha: 0.06),
                  ),
                ),
                LineChartBarData(
                  spots: rightSpots,
                  isCurved: true, curveSmoothness: 0.35,
                  color: AppColors.accentOrange,
                  barWidth: 1.8,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.accentOrange.withValues(alpha: 0.06),
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
    Text(label, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 7.5)),
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
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pressure Metrics', style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 9, fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 6),
          ..._rows(p).map((r) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(children: [
              Expanded(child: Text(r.$1, style: GoogleFonts.inter(
                color: AppColors.textSecondary, fontSize: 9,
              ))),
              Text(r.$2, style: GoogleFonts.inter(
                color: r.$3 ?? AppColors.textPrimary,
                fontSize: 9.5, fontWeight: FontWeight.w700,
              )),
              if (r.$4 != null) ...[
                const SizedBox(width: 4),
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: r.$4,
                  ),
                ),
              ],
            ]),
          )),
        ],
      ),
    );
  }

  List<(String, String, Color?, Color?)> _rows(PlantarData p) => [
    ('Total Load',         '${p.totalLoad.toStringAsFixed(1)} %BW',    null, null),
    ('Heel Load',          '${p.heelLoad.toStringAsFixed(1)} %BW',     null, null),
    ('Forefoot Load',      '${p.forefootLoad.toStringAsFixed(1)} %BW', null, null),
    ('Left / Right Asymmetry', '${p.asymmetry.toStringAsFixed(1)} %',  null, null),
    ('Stability (COP SD)',
      '${p.stability.toStringAsFixed(2)} cm',
      p.stability < 1.0 ? AppColors.accentGreen : AppColors.accentOrange,
      p.stability < 1.0 ? AppColors.accentGreen : AppColors.accentOrange,
    ),
  ];
}
