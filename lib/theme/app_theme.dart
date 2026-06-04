import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background   = Color(0xFF0A1628);
  static const surface      = Color(0xFF0D1F3C);
  static const surfaceLight = Color(0xFF122444);
  static const accent       = Color(0xFF1A6EFA);
  static const accentGreen  = Color(0xFF00C896);
  static const accentOrange = Color(0xFFFF8C00);
  static const accentRed    = Color(0xFFFF3B55);
  static const accentCyan   = Color(0xFF00D4FF);
  static const textPrimary  = Color(0xFFE8EFF8);
  static const textSecondary= Color(0xFF8A9BB5);
  static const border       = Color(0xFF1E3050);
  static const panelHeader  = Color(0xFF0F2040);

  // Heatmap gradient
  static const List<Color> heatmap = [
    Color(0xFF0000FF), Color(0xFF00AAFF), Color(0xFF00FFAA),
    Color(0xFFAAFF00), Color(0xFFFFAA00), Color(0xFFFF0000),
  ];
}

class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.surface,
      primary: AppColors.accent,
      secondary: AppColors.accentCyan,
      error: AppColors.accentRed,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
      bodyMedium: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 13),
      bodySmall: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 11),
      labelLarge: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
    ),
    dividerColor: AppColors.border,
  );
}

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
    this.iconColor = AppColors.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
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
        color: AppColors.panelHeader,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Text(title, style: GoogleFonts.inter(
          color: iconColor, fontSize: 14, fontWeight: FontWeight.w600,
        )),
        const Spacer(),
        if (trailing != null) trailing!,
        Icon(Icons.open_in_new, size: 14, color: AppColors.textSecondary),
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
    this.valueColor = AppColors.textPrimary,
    this.showCheck = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GoogleFonts.inter(
          color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w500,
        ), textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.inter(
          color: valueColor, fontSize: 20, fontWeight: FontWeight.w700,
        )),
        if (target != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(target!, style: GoogleFonts.inter(
              color: AppColors.textSecondary, fontSize: 9,
            )),
            if (showCheck) ...[
              const SizedBox(width: 3),
              const Icon(Icons.check_circle, color: AppColors.accentGreen, size: 10),
            ],
          ]),
      ],
    );
  }
}
