/// How the 3D skeleton figure is drawn in [Skeleton3DView]. Every style renders
/// the *same* recorded joints — only the look changes — so switching is free and
/// works with every recording (no re-processing, no new dependencies).
enum AvatarStyle {
  /// Thin depth-shaded bone lines + small joint dots. Crisp, clinical.
  lines,

  /// Solid tapered limb capsules + lit joint spheres. A rounded mannequin body.
  mannequin,

  /// Glowing thick tubes + bright joints. High-contrast, sci-fi.
  neon,

  /// Flat rectangular limb segments + block joints. Low-poly / robot look.
  blocky,

  /// Cel-shaded cartoon: oversized head with a billboarded face + hair, chunky
  /// outlined limbs. Anime-inspired (a stylised figure, not a rigged character).
  cartoon,
}

extension AvatarStyleInfo on AvatarStyle {
  /// Stable string persisted in settings — do not rename tokens.
  String get token => switch (this) {
        AvatarStyle.lines => 'lines',
        AvatarStyle.mannequin => 'mannequin',
        AvatarStyle.neon => 'neon',
        AvatarStyle.blocky => 'blocky',
        AvatarStyle.cartoon => 'cartoon',
      };

  String get label => switch (this) {
        AvatarStyle.lines => 'Lines',
        AvatarStyle.mannequin => 'Mannequin',
        AvatarStyle.neon => 'Neon',
        AvatarStyle.blocky => 'Blocky',
        AvatarStyle.cartoon => 'Cartoon',
      };

  String get description => switch (this) {
        AvatarStyle.lines => 'Thin bone lines & joint dots — crisp and clinical',
        AvatarStyle.mannequin => 'Solid rounded body — capsules & spheres',
        AvatarStyle.neon => 'Glowing tubes & bright joints',
        AvatarStyle.blocky => 'Flat rectangular segments — low-poly / robot',
        AvatarStyle.cartoon => 'Anime-inspired: big head, face & hair, bold outlines',
      };

  static AvatarStyle fromToken(String? t) => switch (t) {
        'mannequin' => AvatarStyle.mannequin,
        'neon' => AvatarStyle.neon,
        'blocky' => AvatarStyle.blocky,
        'cartoon' => AvatarStyle.cartoon,
        _ => AvatarStyle.lines,
      };
}
