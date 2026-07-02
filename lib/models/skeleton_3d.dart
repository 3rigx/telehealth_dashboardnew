import 'dart:math';

/// A minimal 3D vector. Coordinate convention used throughout the app:
///   +X = subject's viewer-left, +Y = up, +Z = toward the camera.
/// Units are metres (matching what the ZED SDK emits), but the renderer
/// is scale-independent so any consistent unit works.
class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  /// Rotate around the vertical (Y) axis — yaw / orbit.
  Vec3 rotateY(double a) {
    final c = cos(a), s = sin(a);
    return Vec3(c * x + s * z, y, -s * x + c * z);
  }

  /// Rotate around the horizontal (X) axis — pitch / tilt.
  Vec3 rotateX(double a) {
    final c = cos(a), s = sin(a);
    return Vec3(x, c * y - s * z, s * y + c * z);
  }

  static Vec3 lerp(Vec3 a, Vec3 b, double t) =>
      Vec3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);

  factory Vec3.fromJson(dynamic j) {
    // Accept either [x,y,z] or {"x":..,"y":..,"z":..}
    if (j is List && j.length >= 3) {
      return Vec3(j[0].toDouble(), j[1].toDouble(), j[2].toDouble());
    }
    if (j is Map) {
      return Vec3(
        (j['x'] ?? 0).toDouble(),
        (j['y'] ?? 0).toDouble(),
        (j['z'] ?? 0).toDouble(),
      );
    }
    return const Vec3(0, 0, 0);
  }
}

/// One bone = a connection between two named joints, plus a flag marking it as
/// part of the currently exercised limb so the renderer can emphasise it.
class Bone {
  final String a, b;
  final bool active;
  const Bone(this.a, this.b, {this.active = false});
}

/// A format-agnostic skeleton: a map of named joints to 3D positions, plus the
/// bone topology. Because joints are keyed by name, the Unity side can send
/// whatever subset the ZED body model produces (BODY_18 / 34 / 38) as long as
/// the names match — see [defaultBones].
class Skeleton3D {
  final Map<String, Vec3> joints;
  final Map<String, double> confidence; // 0..1 per joint, optional
  final List<Bone> bones;

  /// Name of the joint whose flexion angle is the focus (e.g. the right knee
  /// during a seated knee-extension trial). Drives the on-figure angle arc.
  final String? activeJoint;
  final double? activeAngle; // degrees, supplied by Unity or computed in demo

  const Skeleton3D({
    required this.joints,
    this.confidence = const {},
    this.bones = defaultBones,
    this.activeJoint,
    this.activeAngle,
  });

  Vec3? operator [](String name) => joints[name];

  /// Centroid of all joints — used as the orbit pivot so rotation feels natural.
  Vec3 get center {
    if (joints.isEmpty) return const Vec3(0, 0, 0);
    var sum = const Vec3(0, 0, 0);
    for (final v in joints.values) {
      sum = sum + v;
    }
    return sum * (1.0 / joints.length);
  }

  factory Skeleton3D.fromJson(Map<String, dynamic> j) {
    final raw = (j['joints'] ?? {}) as Map<String, dynamic>;
    final joints = <String, Vec3>{};
    final conf = <String, double>{};
    raw.forEach((name, value) {
      joints[name] = Vec3.fromJson(value);
      if (value is Map && value['c'] != null) {
        conf[name] = (value['c']).toDouble();
      }
    });
    return Skeleton3D(
      joints: joints,
      confidence: conf,
      activeJoint: j['activeJoint'],
      activeAngle: (j['activeAngle'])?.toDouble(),
    );
  }

  /// Standard human topology keyed by the joint names the demo + Unity emit.
  static const List<Bone> defaultBones = [
    // Spine + head
    Bone('pelvis', 'chest'),
    Bone('chest', 'neck'),
    Bone('neck', 'head'),
    // Shoulders + arms
    Bone('chest', 'shoulderL'),
    Bone('chest', 'shoulderR'),
    Bone('shoulderL', 'elbowL'),
    Bone('elbowL', 'wristL'),
    Bone('shoulderR', 'elbowR'),
    Bone('elbowR', 'wristR'),
    // Pelvis + legs
    Bone('pelvis', 'hipL'),
    Bone('pelvis', 'hipR'),
    Bone('hipL', 'kneeL'),
    Bone('kneeL', 'ankleL'),
    Bone('ankleL', 'toeL'),
    // Right leg = the actively exercised limb in the demo
    Bone('hipR', 'kneeR', active: true),
    Bone('kneeR', 'ankleR', active: true),
    Bone('ankleR', 'toeR', active: true),
  ];

  /// Builds a seated figure performing right-leg knee extension.
  /// [kneeAngleDeg] is measured from the horizontal thigh: 0° = fully extended
  /// (shin horizontal/forward), 90° = shin hanging straight down. This matches
  /// the semantics already used in [JointAngleData].
  static Skeleton3D seatedDemo({
    required double kneeAngleDeg,
    double targetMid = 50,
  }) {
    const thigh = 0.42, shin = 0.42, foot = 0.16;
    final aR = kneeAngleDeg * pi / 180.0;
    const aL = 80 * pi / 180.0; // resting (static) left shin hangs down

    final hipR = const Vec3(-0.11, -0.02, 0.0);
    final hipL = const Vec3(0.11, -0.02, 0.0);
    final kneeR = hipR + const Vec3(0, -0.04, thigh);
    final kneeL = hipL + const Vec3(0, -0.04, thigh);
    final ankleR = kneeR + Vec3(0, -shin * sin(aR), shin * cos(aR));
    final ankleL = kneeL + Vec3(0, -shin * sin(aL), shin * cos(aL));

    final joints = <String, Vec3>{
      'pelvis': const Vec3(0, 0, 0),
      'chest': const Vec3(0, 0.45, -0.02),
      'neck': const Vec3(0, 0.58, -0.02),
      'head': const Vec3(0, 0.74, 0.0),
      'shoulderL': const Vec3(0.19, 0.50, -0.02),
      'shoulderR': const Vec3(-0.19, 0.50, -0.02),
      'elbowL': const Vec3(0.23, 0.27, 0.08),
      'elbowR': const Vec3(-0.23, 0.27, 0.08),
      'wristL': const Vec3(0.20, 0.07, 0.20),
      'wristR': const Vec3(-0.20, 0.07, 0.20),
      'hipL': hipL,
      'hipR': hipR,
      'kneeL': kneeL,
      'kneeR': kneeR,
      'ankleL': ankleL,
      'ankleR': ankleR,
      'toeL': ankleL + const Vec3(0, -0.02, foot),
      'toeR': ankleR + Vec3(0, -0.02 * cos(aR), foot * cos(aR) + 0.04),
    };

    return Skeleton3D(
      joints: joints,
      activeJoint: 'kneeR',
      activeAngle: kneeAngleDeg,
    );
  }
}
