import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/avatar_style.dart';
import '../models/skeleton_3d.dart';
import '../services/app_settings.dart';
import '../theme/app_theme.dart';

/// Interactive 3D telemetry view of a [Skeleton3D].
///
/// Renders the skeleton with a lightweight perspective projection (no external
/// 3D engine — a body is only ~18 points and ~17 bones, so a CustomPainter is
/// faster and fully controllable). Supports:
///   • drag to orbit, mouse-wheel to zoom
///   • a solid body: tapered depth-shaded limb capsules + lit joint spheres,
///     nearer = brighter, painter's-algorithm sorted
///   • a 3D angle arc drawn at the active joint
///   • a faint "target pose" ghost shin showing the clinical goal
///   • idle auto-rotate that pauses while the user interacts
class Skeleton3DView extends StatefulWidget {
  final Skeleton3D skeleton;

  /// Optional clinical target range for the active joint, used to colour the
  /// active limb green (in-range) or orange (out-of-range) and draw the ghost.
  final double? targetMin;
  final double? targetMax;

  /// Figure style. When null (the usual case) the user's Settings choice is
  /// used; pass an explicit value to force a look (e.g. the settings preview).
  final AvatarStyle? style;

  const Skeleton3DView({
    super.key,
    required this.skeleton,
    this.targetMin,
    this.targetMax,
    this.style,
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
    final style = widget.style ?? context.watch<AppSettings>().avatarStyle;
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
              style: style,
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
  final AvatarStyle style;
  final double? targetMin, targetMax;

  static const double _camDist = 3.2;

  /// World-space limb thickness (radius, in the same metres as the joints) used
  /// to draw the figure as a solid body rather than thin sticks. Torso/head are
  /// bulky, limbs taper toward the extremities. Projected perspective-correctly,
  /// so it scales with zoom/distance like the rest of the figure.
  static const Map<String, double> _girth = {
    'pelvis': 0.100,
    'chest': 0.115,
    'neck': 0.050,
    'head': 0.100,
    'shoulderL': 0.062, 'shoulderR': 0.062,
    'elbowL': 0.046, 'elbowR': 0.046,
    'wristL': 0.032, 'wristR': 0.032,
    'hipL': 0.078, 'hipR': 0.078,
    'kneeL': 0.056, 'kneeR': 0.056,
    'ankleL': 0.042, 'ankleR': 0.042,
    'toeL': 0.030, 'toeR': 0.030,
  };
  static double _girthOf(String name) => _girth[name] ?? 0.050;

  const _Skeleton3DPainter({
    required this.skeleton,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.style,
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

    // ── the body itself, in the user-selected style ───────────────────
    // Every style renders the same projected joints; only the look differs.
    switch (style) {
      case AvatarStyle.lines:
        _styleLines(canvas, pts, shade, activeColor);
      case AvatarStyle.mannequin:
        _styleMannequin(canvas, pts, shade, activeColor, focal);
      case AvatarStyle.neon:
        _styleNeon(canvas, pts, shade, activeColor, focal);
      case AvatarStyle.blocky:
        _styleBlocky(canvas, pts, shade, activeColor, focal);
      case AvatarStyle.cartoon:
        _styleCartoon(canvas, pts, shade, activeColor, focal);
    }

    // ── 3D angle arc at the active joint ───────────────────────────────
    _drawAngleArc(canvas, project, activeColor);
  }

  // Bones sorted far-to-near (painter's algorithm) for the current camera.
  List<Bone> _sortedBones(Map<String, _P> pts) {
    final bones = [...skeleton.bones];
    bones.sort((a, b) {
      final da = ((pts[a.a]?.depth ?? 0) + (pts[a.b]?.depth ?? 0)) / 2;
      final db = ((pts[b.a]?.depth ?? 0) + (pts[b.b]?.depth ?? 0)) / 2;
      return db.compareTo(da);
    });
    return bones;
  }

  // Joints sorted far-to-near so nearer ones paint on top.
  List<MapEntry<String, _P>> _sortedJoints(Map<String, _P> pts) =>
      pts.entries.toList()
        ..sort((a, b) => b.value.depth.compareTo(a.value.depth));

  // Screen-space unit direction + perpendicular for a bone; null if degenerate.
  ({Offset u, Offset n})? _axis(Offset a, Offset b) {
    final dir = b - a;
    final len = dir.distance;
    if (len < 0.001) return null;
    final u = dir / len;
    return (u: u, n: Offset(-u.dy, u.dx));
  }

  // ── Style: LINES — the classic thin stickman ─────────────────────────
  void _styleLines(Canvas canvas, Map<String, _P> pts,
      double Function(double) shade, Color activeColor) {
    for (final bone in _sortedBones(pts)) {
      final pa = pts[bone.a], pb = pts[bone.b];
      if (pa == null || pb == null) continue;
      final t = (shade(pa.depth) + shade(pb.depth)) / 2;
      final base = bone.active ? activeColor : AppColors.accent;
      final col = Color.lerp(base.withValues(alpha: 0.30), base, t)!;
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
    for (final e in _sortedJoints(pts)) {
      final t = shade(e.value.depth);
      final isActive = e.key == skeleton.activeJoint;
      final r = (isActive ? 7.0 : 4.0) * (0.7 + 0.3 * t);
      final col = isActive ? activeColor : AppColors.accentCyan;
      canvas.drawCircle(
          e.value.s, r + 3, Paint()..color = col.withValues(alpha: 0.16 * t));
      canvas.drawCircle(e.value.s, r,
          Paint()..color = Color.lerp(col.withValues(alpha: 0.4), col, t)!);
      canvas.drawCircle(
        e.value.s,
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5 * t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    }
  }

  // ── Style: MANNEQUIN — solid tapered capsules + lit spheres ──────────
  void _styleMannequin(Canvas canvas, Map<String, _P> pts,
      double Function(double) shade, Color activeColor, double focal) {
    const shadow = Color(0xFF0A1120);
    for (final bone in _sortedBones(pts)) {
      final pa = pts[bone.a], pb = pts[bone.b];
      if (pa == null || pb == null) continue;
      final ax = _axis(pa.s, pb.s);
      if (ax == null) continue;
      final t = (shade(pa.depth) + shade(pb.depth)) / 2;
      final base = bone.active ? activeColor : AppColors.accent;
      final col = Color.lerp(Color.lerp(base, shadow, 0.45)!, base, t)!;
      final rA = _girthOf(bone.a) * focal / max(pa.depth, 0.1);
      final rB = _girthOf(bone.b) * focal / max(pb.depth, 0.1);
      final n = ax.n;
      final capsule = Path()
        ..moveTo(pa.s.dx + n.dx * rA, pa.s.dy + n.dy * rA)
        ..lineTo(pb.s.dx + n.dx * rB, pb.s.dy + n.dy * rB)
        ..lineTo(pb.s.dx - n.dx * rB, pb.s.dy - n.dy * rB)
        ..lineTo(pa.s.dx - n.dx * rA, pa.s.dy - n.dy * rA)
        ..close();
      final fill = Paint()..color = col;
      canvas.drawPath(capsule, fill);
      canvas.drawCircle(pa.s, rA, fill); // rounded caps
      canvas.drawCircle(pb.s, rB, fill);
      canvas.drawLine(
        pa.s,
        pb.s,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.10 * t)
          ..strokeWidth = min(rA, rB) * 0.9
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final e in _sortedJoints(pts)) {
      final t = shade(e.value.depth);
      final isActive = e.key == skeleton.activeJoint;
      final base = isActive ? activeColor : AppColors.accent;
      final r = _girthOf(e.key) * focal / max(e.value.depth, 0.1);
      final rect = Rect.fromCircle(center: e.value.s, radius: r);
      final lit = Color.lerp(base, Colors.white, 0.55 * t)!;
      final mid = Color.lerp(base, shadow, 0.15)!;
      final edge = Color.lerp(base, const Color(0xFF06090F), 0.55)!;
      canvas.drawCircle(
        e.value.s,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.45, -0.5), // light from upper-left
            radius: 1.05,
            colors: [lit, mid, edge],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(rect),
      );
      if (isActive) {
        canvas.drawCircle(
          e.value.s,
          r,
          Paint()
            ..color = base.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
    }
  }

  // ── Style: NEON — glowing tubes + bright joints ──────────────────────
  void _styleNeon(Canvas canvas, Map<String, _P> pts,
      double Function(double) shade, Color activeColor, double focal) {
    for (final bone in _sortedBones(pts)) {
      final pa = pts[bone.a], pb = pts[bone.b];
      if (pa == null || pb == null) continue;
      final t = (shade(pa.depth) + shade(pb.depth)) / 2;
      final base = bone.active ? activeColor : AppColors.accentCyan;
      canvas.drawLine(
        pa.s,
        pb.s,
        Paint()
          ..color = base.withValues(alpha: 0.35 * (0.5 + 0.5 * t))
          ..strokeWidth = bone.active ? 16 : 12
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawLine(
        pa.s,
        pb.s,
        Paint()
          ..color = base.withValues(alpha: 0.9)
          ..strokeWidth = bone.active ? 6 : 4.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        pa.s,
        pb.s,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.75 * t)
          ..strokeWidth = bone.active ? 2 : 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final e in _sortedJoints(pts)) {
      final t = shade(e.value.depth);
      final isActive = e.key == skeleton.activeJoint;
      final base = isActive ? activeColor : AppColors.accentCyan;
      final r = (isActive ? 7.0 : 5.0) * (0.7 + 0.3 * t);
      canvas.drawCircle(
        e.value.s,
        r * 2.2,
        Paint()
          ..color = base.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(e.value.s, r, Paint()..color = base);
      canvas.drawCircle(e.value.s, r * 0.5,
          Paint()..color = Colors.white.withValues(alpha: 0.85 * t));
    }
  }

  // ── Style: BLOCKY — flat rectangular segments + block joints ─────────
  void _styleBlocky(Canvas canvas, Map<String, _P> pts,
      double Function(double) shade, Color activeColor, double focal) {
    const shadow = Color(0xFF0A1120);
    for (final bone in _sortedBones(pts)) {
      final pa = pts[bone.a], pb = pts[bone.b];
      if (pa == null || pb == null) continue;
      final ax = _axis(pa.s, pb.s);
      if (ax == null) continue;
      final t = (shade(pa.depth) + shade(pb.depth)) / 2;
      final base = bone.active ? activeColor : AppColors.accent;
      final col = Color.lerp(Color.lerp(base, shadow, 0.45)!, base, t)!;
      // constant half-width from the thicker joint (no taper → chunky segments)
      final avgDepth = max((pa.depth + pb.depth) / 2, 0.1);
      final w = max(_girthOf(bone.a), _girthOf(bone.b)) * focal / avgDepth;
      final n = ax.n;
      final rect = Path()
        ..moveTo(pa.s.dx + n.dx * w, pa.s.dy + n.dy * w)
        ..lineTo(pb.s.dx + n.dx * w, pb.s.dy + n.dy * w)
        ..lineTo(pb.s.dx - n.dx * w, pb.s.dy - n.dy * w)
        ..lineTo(pa.s.dx - n.dx * w, pa.s.dy - n.dy * w)
        ..close();
      canvas.drawPath(rect, Paint()..color = col);
      // shade one half for a panelled, faceted look
      final facet = Path()
        ..moveTo(pa.s.dx, pa.s.dy)
        ..lineTo(pb.s.dx, pb.s.dy)
        ..lineTo(pb.s.dx - n.dx * w, pb.s.dy - n.dy * w)
        ..lineTo(pa.s.dx - n.dx * w, pa.s.dy - n.dy * w)
        ..close();
      canvas.drawPath(facet, Paint()..color = shadow.withValues(alpha: 0.22));
      canvas.drawPath(
        rect,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    for (final e in _sortedJoints(pts)) {
      final t = shade(e.value.depth);
      final isActive = e.key == skeleton.activeJoint;
      final base = isActive ? activeColor : AppColors.accent;
      final col = Color.lerp(Color.lerp(base, shadow, 0.35)!, base, t)!;
      final r = _girthOf(e.key) * focal / max(e.value.depth, 0.1);
      final box = Rect.fromCenter(center: e.value.s, width: r * 2, height: r * 2);
      final rr = RRect.fromRectAndRadius(box, Radius.circular(r * 0.28));
      canvas.drawRRect(rr, Paint()..color = col);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  // A tapered capsule quad between two screen points (caps drawn separately).
  Path _capsulePath(Offset a, Offset b, double rA, double rB, Offset n) => Path()
    ..moveTo(a.dx + n.dx * rA, a.dy + n.dy * rA)
    ..lineTo(b.dx + n.dx * rB, b.dy + n.dy * rB)
    ..lineTo(b.dx - n.dx * rB, b.dy - n.dy * rB)
    ..lineTo(a.dx - n.dx * rA, a.dy - n.dy * rA)
    ..close();

  // ── Style: CARTOON — anime-inspired chibi (big head, face, hair) ─────
  void _styleCartoon(Canvas canvas, Map<String, _P> pts,
      double Function(double) shade, Color activeColor, double focal) {
    const outline = Color(0xFF2A1F3D); // ink outline
    const skin = Color(0xFFFFD9B8);
    const skinShadow = Color(0xFFEBB489);
    final clothes = AppColors.accentCyan; // shirt/pants
    final clothesShadow = Color.lerp(AppColors.accentCyan, Colors.black, 0.30)!;
    final hair = AppColors.accent; // violet hair
    final hairShadow = Color.lerp(AppColors.accent, Colors.black, 0.35)!;
    const ow = 3.0; // outline thickness (px)

    const torso = {'pelvis', 'chest', 'neck', 'shoulderL', 'shoulderR', 'hipL', 'hipR'};
    bool isTorso(Bone b) => torso.contains(b.a) && torso.contains(b.b);
    double capR(String j) => _girthOf(j) * 1.28; // chunky cartoon limbs

    // ── body: outlined, cel-shaded capsules (skip neck→head; head is drawn
    //    on top as a big cartoon head) ────────────────────────────────────
    for (final bone in _sortedBones(pts)) {
      if (bone.a == 'head' || bone.b == 'head') continue;
      final pa = pts[bone.a], pb = pts[bone.b];
      if (pa == null || pb == null) continue;
      final ax = _axis(pa.s, pb.s);
      if (ax == null) continue;
      final n = ax.n;
      final base = bone.active
          ? activeColor
          : (isTorso(bone) ? clothes : skin);
      final shadowCol = bone.active
          ? Color.lerp(activeColor, Colors.black, 0.30)!
          : (isTorso(bone) ? clothesShadow : skinShadow);
      final rA = capR(bone.a) * focal / max(pa.depth, 0.1);
      final rB = capR(bone.b) * focal / max(pb.depth, 0.1);

      // ink outline (a larger dark capsule behind the fill)
      final inkPaint = Paint()..color = outline;
      canvas.drawPath(_capsulePath(pa.s, pb.s, rA + ow, rB + ow, n), inkPaint);
      canvas.drawCircle(pa.s, rA + ow, inkPaint);
      canvas.drawCircle(pb.s, rB + ow, inkPaint);
      // flat fill
      final fillPaint = Paint()..color = base;
      canvas.drawPath(_capsulePath(pa.s, pb.s, rA, rB, n), fillPaint);
      canvas.drawCircle(pa.s, rA, fillPaint);
      canvas.drawCircle(pb.s, rB, fillPaint);
      // single cel shadow on the lower/back half
      final facet = Path()
        ..moveTo(pa.s.dx, pa.s.dy)
        ..lineTo(pb.s.dx, pb.s.dy)
        ..lineTo(pb.s.dx - n.dx * rB, pb.s.dy - n.dy * rB)
        ..lineTo(pa.s.dx - n.dx * rA, pa.s.dy - n.dy * rA)
        ..close();
      canvas.drawPath(facet, Paint()..color = shadowCol.withValues(alpha: 0.5));
    }

    // ── the big cartoon head + billboarded face ────────────────────────
    final headP = pts['head'], neckP = pts['neck'];
    if (headP != null) {
      // sit a large head above the neck for a chibi silhouette
      final up = neckP == null
          ? const Offset(0, -1)
          : (headP.s - neckP.s);
      final upLen = up.distance;
      final upN = upLen < 0.001 ? const Offset(0, -1) : up / upLen;
      final R = _girthOf('head') * 2.15 * focal / max(headP.depth, 0.1);
      final c = headP.s + upN * (R * 0.35);

      // hair back-blob (slightly larger, drawn behind the face)
      canvas.drawCircle(c, R + ow, Paint()..color = outline);
      canvas.drawCircle(c, R, Paint()..color = hair);
      // face (skin) — offset down so hair frames the top
      final faceC = c + upN * (-R * 0.16);
      final faceR = R * 0.92;
      canvas.drawCircle(faceC, faceR + ow, Paint()..color = outline);
      canvas.drawCircle(faceC, faceR, Paint()..color = skin);
      // soft skin shadow on the lower face
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: faceC, radius: faceR)));
      canvas.drawCircle(faceC + Offset(0, faceR * 0.55), faceR * 0.9,
          Paint()..color = skinShadow.withValues(alpha: 0.35));
      canvas.restore();

      // bangs: a few hair tufts hanging over the forehead
      final bangY = faceC.dy - faceR * 0.45;
      for (final bx in [-0.5, -0.15, 0.2, 0.55]) {
        final tip = Offset(faceC.dx + faceR * bx, bangY + faceR * 0.5);
        final tuft = Path()
          ..moveTo(faceC.dx + faceR * (bx - 0.22), bangY - faceR * 0.1)
          ..lineTo(faceC.dx + faceR * (bx + 0.22), bangY - faceR * 0.1)
          ..lineTo(tip.dx, tip.dy)
          ..close();
        canvas.drawPath(tuft, Paint()..color = hair);
        canvas.drawPath(
          tuft,
          Paint()
            ..color = hairShadow.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      }

      // eyes (big anime eyes, billboarded toward the viewer)
      final eyeY = faceC.dy + faceR * 0.12;
      final eyeDX = faceR * 0.40;
      final eyeW = faceR * 0.30, eyeH = faceR * 0.44;
      for (final sx in [-1.0, 1.0]) {
        final ec = Offset(faceC.dx + sx * eyeDX, eyeY);
        // white
        canvas.drawOval(
            Rect.fromCenter(center: ec, width: eyeW, height: eyeH),
            Paint()..color = Colors.white);
        // iris
        canvas.drawCircle(ec + Offset(0, eyeH * 0.05), eyeW * 0.42,
            Paint()..color = hair);
        canvas.drawCircle(ec + Offset(0, eyeH * 0.05), eyeW * 0.22,
            Paint()..color = outline);
        // highlight
        canvas.drawCircle(ec + Offset(-eyeW * 0.14, -eyeH * 0.14), eyeW * 0.12,
            Paint()..color = Colors.white);
        // upper lash line
        canvas.drawArc(
          Rect.fromCenter(center: ec, width: eyeW, height: eyeH),
          3.6, 2.1,
          false,
          Paint()
            ..color = outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round,
        );
      }

      // blush
      for (final sx in [-1.0, 1.0]) {
        canvas.drawCircle(
          Offset(faceC.dx + sx * faceR * 0.58, faceC.dy + faceR * 0.34),
          faceR * 0.14,
          Paint()..color = const Color(0xFFFF8FA3).withValues(alpha: 0.5),
        );
      }

      // mouth: a tiny smile
      final mouth = Rect.fromCenter(
          center: Offset(faceC.dx, faceC.dy + faceR * 0.48),
          width: faceR * 0.30,
          height: faceR * 0.22);
      canvas.drawArc(
        mouth,
        0.35, 2.44,
        false,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    }
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
      old.style != style ||
      old.skeleton != skeleton ||
      old.targetMin != targetMin ||
      old.targetMax != targetMax;
}
