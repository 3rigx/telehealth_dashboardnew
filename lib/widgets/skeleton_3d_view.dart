import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/skeleton_3d.dart';
import '../theme/app_theme.dart';

/// Interactive 3D telemetry view of a [Skeleton3D].
///
/// Renders the skeleton with a lightweight perspective projection (no external
/// 3D engine — a body is only ~18 points and ~17 bones, so a CustomPainter is
/// faster and fully controllable). Supports:
///   • drag to orbit, mouse-wheel to zoom
///   • depth-shaded bones (nearer = brighter) with painter's-algorithm sorting
///   • a 3D angle arc drawn at the active joint
///   • a faint "target pose" ghost shin showing the clinical goal
///   • idle auto-rotate that pauses while the user interacts
class Skeleton3DView extends StatefulWidget {
  final Skeleton3D skeleton;

  /// Optional clinical target range for the active joint, used to colour the
  /// active limb green (in-range) or orange (out-of-range) and draw the ghost.
  final double? targetMin;
  final double? targetMax;

  const Skeleton3DView({
    super.key,
    required this.skeleton,
    this.targetMin,
    this.targetMax,
  });

  @override
  State<Skeleton3DView> createState() => _Skeleton3DViewState();
}

class _Skeleton3DViewState extends State<Skeleton3DView>
    with SingleTickerProviderStateMixin {
  // Camera state.
  double _yaw = -0.55;   // start at a 3/4 view so leg extension reads clearly
  double _pitch = 0.12;
  double _zoom = 2.3;

  bool _autoRotate = true;
  late final AnimationController _idle;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    _idle.addListener(() {
      if (_autoRotate && mounted) setState(() => _yaw += 0.0016);
    });
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  void _resetView() => setState(() {
        _yaw = -0.55;
        _pitch = 0.12;
        _zoom = 2.3;
      });

  /// One-click camera presets: ¾ view, front, side, top.
  void _preset(double yaw, double pitch) => setState(() {
        _autoRotate = false;
        _yaw = yaw;
        _pitch = pitch;
      });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          setState(() {
            _zoom = (_zoom - e.scrollDelta.dy * 0.0015).clamp(1.0, 5.0);
          });
        }
      },
      child: GestureDetector(
        onPanStart: (_) => setState(() => _autoRotate = false),
        onPanUpdate: (d) => setState(() {
          _yaw += d.delta.dx * 0.01;
          _pitch = (_pitch + d.delta.dy * 0.01).clamp(-1.2, 1.2);
        }),
        child: Stack(fit: StackFit.expand, children: [
          CustomPaint(
            painter: _Skeleton3DPainter(
              skeleton: widget.skeleton,
              yaw: _yaw,
              pitch: _pitch,
              zoom: _zoom,
              targetMin: widget.targetMin,
              targetMax: widget.targetMax,
            ),
            child: const SizedBox.expand(),
          ),
          // ── overlay controls ──────────────────────────────────────────
          Positioned(
            top: 8,
            right: 8,
            child: Row(children: [
              _ctrlBtn(
                _autoRotate ? Icons.pause : Icons.threesixty,
                () => setState(() => _autoRotate = !_autoRotate),
                tip: _autoRotate ? 'Pause rotation' : 'Auto-rotate',
              ),
              const SizedBox(width: 6),
              _ctrlBtn(Icons.center_focus_strong, _resetView, tip: 'Reset view'),
            ]),
          ),
          // ── view-mode presets ─────────────────────────────────────────
          Positioned(
            top: 8,
            left: 8,
            child: Row(children: [
              _presetBtn('¾', 'Three-quarter view', () => _preset(-0.55, 0.12)),
              const SizedBox(width: 4),
              _presetBtn('Front', 'Front view', () => _preset(0, 0)),
              const SizedBox(width: 4),
              _presetBtn('Side', 'Side view', () => _preset(pi / 2, 0)),
              const SizedBox(width: 4),
              _presetBtn('Top', 'Top-down view', () => _preset(-0.55, 1.15)),
            ]),
          ),
          Positioned(
            bottom: 6,
            left: 8,
            child: Row(children: [
              const Icon(Icons.threed_rotation,
                  size: 11, color: AppColors.accentCyan),
              const SizedBox(width: 4),
              Text(
                'Drag to orbit · scroll to zoom',
                style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.inkMuted.withValues(alpha: 0.8),
                  fontSize: 9,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _presetBtn(String label, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.inkBorder.withValues(alpha: 0.6)),
          ),
          child: Text(label,
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.inkMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _ctrlBtn(IconData icon, VoidCallback onTap, {required String tip}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.inkBorder.withValues(alpha: 0.6)),
          ),
          child: Icon(icon, size: 14, color: AppColors.inkMuted),
        ),
      ),
    );
  }
}

/// Projected screen position + camera-space depth (smaller = nearer).
class _P {
  final Offset s;
  final double depth;
  const _P(this.s, this.depth);
}

class _Skeleton3DPainter extends CustomPainter {
  final Skeleton3D skeleton;
  final double yaw, pitch, zoom;
  final double? targetMin, targetMax;

  static const double _camDist = 3.2;

  const _Skeleton3DPainter({
    required this.skeleton,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    this.targetMin,
    this.targetMax,
  });

  bool get _inTarget {
    final a = skeleton.activeAngle;
    if (a == null || targetMin == null || targetMax == null) return true;
    return a >= targetMin! && a <= targetMax!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || skeleton.joints.isEmpty) return;

    final pivot = skeleton.center;
    final focal = size.shortestSide * zoom;
    final cx = size.width / 2;
    final cy = size.height / 2 + size.height * 0.06; // nudge figure up a touch

    _P project(Vec3 world) {
      final r = (world - pivot).rotateY(yaw).rotateX(pitch);
      final viewDepth = _camDist - r.z; // camera at +z looking toward -z
      final f = focal / max(viewDepth, 0.1);
      return _P(Offset(cx + r.x * f, cy - r.y * f), viewDepth);
    }

    // ── background gradient ────────────────────────────────────────────
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.1,
          colors: [Color(0xFF0B1A33), Color(0xFF050B17)],
        ).createShader(Offset.zero & size),
    );

    _drawFloorGrid(canvas, project);

    // Project every joint once.
    final pts = <String, _P>{};
    skeleton.joints.forEach((name, v) => pts[name] = project(v));

    // Depth range for shading.
    var dMin = double.infinity, dMax = -double.infinity;
    for (final p in pts.values) {
      dMin = min(dMin, p.depth);
      dMax = max(dMax, p.depth);
    }
    double shade(double depth) =>
        dMax > dMin ? 1 - ((depth - dMin) / (dMax - dMin)) : 1.0;

    final activeColor = _inTarget ? AppColors.accentGreen : AppColors.accentOrange;

    // ── target-pose ghost (drawn behind the live skeleton) ─────────────
    _drawTargetGhost(canvas, project);

    // ── bones, far-to-near (painter's algorithm) ───────────────────────
    final bones = [...skeleton.bones];
    bones.sort((a, b) {
      final da = ((pts[a.a]?.depth ?? 0) + (pts[a.b]?.depth ?? 0)) / 2;
      final db = ((pts[b.a]?.depth ?? 0) + (pts[b.b]?.depth ?? 0)) / 2;
      return db.compareTo(da);
    });

    for (final bone in bones) {
      final pa = pts[bone.a], pb = pts[bone.b];
      if (pa == null || pb == null) continue;
      final t = (shade(pa.depth) + shade(pb.depth)) / 2;
      final base = bone.active ? activeColor : AppColors.accent;
      final col = Color.lerp(base.withValues(alpha: 0.30), base, t)!;

      // soft glow under the line
      canvas.drawLine(
        pa.s,
        pb.s,
        Paint()
          ..color = col.withValues(alpha: 0.18)
          ..strokeWidth = bone.active ? 9 : 7
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        pa.s,
        pb.s,
        Paint()
          ..color = col
          ..strokeWidth = bone.active ? 4 : 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── joints ─────────────────────────────────────────────────────────
    final ordered = pts.entries.toList()
      ..sort((a, b) => b.value.depth.compareTo(a.value.depth));
    for (final e in ordered) {
      final t = shade(e.value.depth);
      final isActive = e.key == skeleton.activeJoint;
      final r = (isActive ? 7.0 : 4.0) * (0.7 + 0.3 * t);
      final col = isActive ? activeColor : AppColors.accentCyan;
      canvas.drawCircle(
        e.value.s,
        r + 3,
        Paint()..color = col.withValues(alpha: 0.16 * t),
      );
      canvas.drawCircle(
        e.value.s,
        r,
        Paint()..color = Color.lerp(col.withValues(alpha: 0.4), col, t)!,
      );
      canvas.drawCircle(
        e.value.s,
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5 * t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    }

    // ── 3D angle arc at the active joint ───────────────────────────────
    _drawAngleArc(canvas, project, activeColor);
  }

  // Floor reference grid on the y-plane just below the feet.
  void _drawFloorGrid(Canvas canvas, _P Function(Vec3) project) {
    double floorY = double.infinity;
    for (final v in skeleton.joints.values) {
      floorY = min(floorY, v.y);
    }
    floorY -= 0.05;
    final paint = Paint()
      ..color = AppColors.inkBorder.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (double gx = -0.8; gx <= 0.8001; gx += 0.2) {
      canvas.drawLine(
        project(Vec3(gx, floorY, -0.3)).s,
        project(Vec3(gx, floorY, 1.0)).s,
        paint,
      );
    }
    for (double gz = -0.3; gz <= 1.0001; gz += 0.2) {
      canvas.drawLine(
        project(Vec3(-0.8, floorY, gz)).s,
        project(Vec3(0.8, floorY, gz)).s,
        paint,
      );
    }
  }

  // Faint shin at the mid-point of the clinical target range.
  void _drawTargetGhost(Canvas canvas, _P Function(Vec3) project) {
    if (skeleton.activeJoint != 'kneeR' ||
        targetMin == null ||
        targetMax == null) {
      return;
    }
    final knee = skeleton['kneeR'];
    final ankle = skeleton['ankleR'];
    if (knee == null || ankle == null) return;

    final shinLen = (ankle - knee).y.abs() + (ankle - knee).z.abs();
    final mid = (targetMin! + targetMax!) / 2 * pi / 180.0;
    final ghostAnkle =
        knee + Vec3(0, -shinLen * sin(mid), shinLen * cos(mid)) * 0.7;

    final pk = project(knee).s, pa = project(ghostAnkle).s;
    canvas.drawLine(
      pk,
      pa,
      Paint()
        ..color = AppColors.accentGreen.withValues(alpha: 0.25)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
        pa, 4, Paint()..color = AppColors.accentGreen.withValues(alpha: 0.3));
  }

  // Sweep an arc in 3D from the thigh direction to the shin direction.
  void _drawAngleArc(
      Canvas canvas, _P Function(Vec3) project, Color color) {
    final aj = skeleton.activeJoint;
    if (aj == null) return;
    final knee = skeleton[aj];
    final hip = skeleton['hipR'];
    final ankle = skeleton['ankleR'];
    if (knee == null || hip == null || ankle == null) return;

    Vec3 norm(Vec3 v) {
      final l = sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
      return l == 0 ? v : v * (1 / l);
    }

    final v1 = norm(hip - knee);
    final v2 = norm(ankle - knee);
    const radius = 0.14;
    const steps = 18;
    final path = Path();
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final dir = norm(Vec3.lerp(v1, v2, t));
      final p = project(knee + dir * radius).s;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accentOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    final a = skeleton.activeAngle;
    if (a != null) {
      final midDir = norm(Vec3.lerp(v1, v2, 0.5));
      final labelPos = project(knee + midDir * (radius + 0.12)).s;
      final tp = TextPainter(
        text: TextSpan(
          text: '${a.toStringAsFixed(0)}°',
          style: GoogleFonts.schibstedGrotesk(
            color: AppColors.accentOrange,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_Skeleton3DPainter old) =>
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.skeleton != skeleton ||
      old.targetMin != targetMin ||
      old.targetMax != targetMax;
}
