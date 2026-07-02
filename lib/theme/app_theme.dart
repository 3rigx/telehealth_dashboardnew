import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Daydream Design System — a friendly, pastel, editorial palette.
/// Soft warm surfaces, a candy-box of pastels for accents, near-black ink for
/// type, and one violet for anything interactive.
///
/// The dashboard is light/editorial ("chrome"), while the dense live-data views
/// (live monitor, replay) sit on the system's Ink surface so the 3D skeleton,
/// heatmaps and charts stay legible — use the `ink*` tokens there.
/// ─────────────────────────────────────────────────────────────────────────
class AppColors {
  // ── Surfaces ───────────────────────────────────────────────────────────
  static const peach = Color(0xFFFFE7D2); // hero & warm sections
  static const sky = Color(0xFFD0F2FF); // cool feature bands
  static const ink = Color(0xFF161616); // dark sections & footer
  static const paper = Color(0xFFFFFFFF); // cards & base

  // ── Pastels (illustration & accents) ─────────────────────────────────────
  static const lavender = Color(0xFFEBDDFB);
  static const lilac = Color(0xFFD9C4F5);
  static const mint = Color(0xFFCFE9D7);
  static const pink = Color(0xFFFAD2E1);
  static const butter = Color(0xFFFBE9B8);
  static const aqua = Color(0xFFBFE4F2);

  // ── Ink & text ───────────────────────────────────────────────────────────
  static const ink900 = Color(0xFF161616);
  static const muted = Color(0xFF6A6A6A);

  // ── Interactive ──────────────────────────────────────────────────────────
  static const violet = Color(0xFF7C4DD6); // links, focus, selection, primary

  // ── Theme mode ────────────────────────────────────────────────────────────
  static bool _dark = false;
  static bool get isDark => _dark;
  static void setDark(bool v) => _dark = v;

  // ── Semantic aliases (mode-aware) ─────────────────────────────────────────
  // `accent` stays Violet in both modes (and const, so it works in const
  // widgets). The rest flip light ↔ ink when dark mode is on.
  static const accent = violet; // primary interactive
  static Color get background => _dark ? const Color(0xFF141414) : const Color(0xFFFBF4EC);
  static Color get surface => _dark ? inkSurface : paper;
  static Color get surfaceLight => _dark ? inkSurfaceAlt : const Color(0xFFF5EFFB);
  static Color get border => _dark ? inkBorder : const Color(0xFFEAE2F2);
  static Color get panelHeader => _dark ? inkSurfaceAlt : peach;
  static Color get textPrimary => _dark ? inkText : ink900;
  static Color get textSecondary => _dark ? inkMuted : muted;

  // Status — kept clearly saturated for safety/legibility on light *and* ink.
  static const accentGreen = Color(0xFF1FB471); // success / connected
  static const accentOrange = Color(0xFFF08A24); // warning / paused
  static const accentRed = Color(0xFFE5484D); // error / recording
  static const accentCyan = Color(0xFF1FA9C9); // info

  // ── Ink-section tokens (dark data views: live monitor, replay, panels) ────
  static const inkBg = Color(0xFF161616);
  static const inkSurface = Color(0xFF1E1E1E);
  static const inkSurfaceAlt = Color(0xFF262626);
  static const inkBorder = Color(0xFF343434);
  static const inkText = Color(0xFFF3EFE8);
  static const inkMuted = Color(0xFF9C9C9C);

  // Heatmap gradient (reads on the ink surfaces).
  static const List<Color> heatmap = [
    Color(0xFF0000FF), Color(0xFF00AAFF), Color(0xFF00FFAA),
    Color(0xFFAAFF00), Color(0xFFFFAA00), Color(0xFFFF0000),
  ];
}

/// Corner radii from the system: chips 8 · cards 18 · panels 28 · pills full.
class AppRadius {
  static const chip = 8.0;
  static const card = 18.0;
  static const panel = 28.0;
  static const pill = 999.0;
}

/// Spacing scale: 4 · 8 · 16 · 24 · 40 · 64.
class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 40.0;
  static const xxl = 64.0;
}

class AppTheme {
  /// Theme reflecting the current AppColors mode. Call `AppColors.setDark(...)`
  /// first, then rebuild the MaterialApp with this.
  static ThemeData get current => _build();
  // Back-compat names — both now reflect the current mode.
  static ThemeData get light => _build();
  static ThemeData get dark => _build();

  static ThemeData _build() {
    final dark = AppColors.isDark;
    final base = dark ? ThemeData.dark() : ThemeData.light();
    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        surface: AppColors.surface,
        primary: AppColors.violet,
        secondary: AppColors.lilac,
        error: AppColors.accentRed,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.schibstedGroteskTextTheme(base.textTheme)
          .apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary)
          .copyWith(
            bodyMedium: GoogleFonts.schibstedGrotesk(color: AppColors.textPrimary, fontSize: 15),
            bodySmall: GoogleFonts.schibstedGrotesk(color: AppColors.textSecondary, fontSize: 13),
            labelLarge: GoogleFonts.schibstedGrotesk(
                color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
      dividerColor: AppColors.border,
      // Pills everywhere, per the system (radius · full).
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: const StadiumBorder(), elevation: 0),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: const StadiumBorder()),
      ),
    );
  }

  /// Caveat handwriting — eyebrows & playful labels ONLY (per the system).
  static TextStyle eyebrow({double size = 17, Color color = AppColors.violet}) =>
      GoogleFonts.caveat(color: color, fontSize: size, fontWeight: FontWeight.w600);
}

/// A dark "Ink" data panel used by the live-monitor & replay visualisations —
/// dark surface so the 3D skeleton / heatmaps / charts stay legible.
class DashboardPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final Widget? trailing;

  const DashboardPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.iconColor = AppColors.violet,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inkSurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.inkBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: title, icon: icon, iconColor: iconColor, trailing: trailing),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget? trailing;

  const _Header({required this.title, required this.icon, required this.iconColor, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.inkSurfaceAlt,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Text(title,
            style: GoogleFonts.schibstedGrotesk(
                color: iconColor, fontSize: 14, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (trailing != null) trailing!,
        const Icon(Icons.open_in_new, size: 14, color: AppColors.inkMuted),
      ]),
    );
  }
}

class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? target;
  final Color valueColor;
  final bool showCheck;

  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.target,
    this.valueColor = AppColors.inkText,
    this.showCheck = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkMuted, fontSize: 10, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.schibstedGrotesk(
                color: valueColor, fontSize: 20, fontWeight: FontWeight.w700)),
        if (target != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(target!,
                style: GoogleFonts.schibstedGrotesk(color: AppColors.inkMuted, fontSize: 9)),
            if (showCheck) ...[
              const SizedBox(width: 3),
              const Icon(Icons.check_circle, color: AppColors.accentGreen, size: 10),
            ],
          ]),
      ],
    );
  }
}
