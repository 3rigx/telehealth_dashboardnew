import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'panels/top_bar.dart';
import 'panels/motion_tracking_panel.dart';
import 'panels/plantar_pressure_panel.dart';
import 'panels/eeg_panel.dart';
import 'panels/fusion_panel.dart';

class LiveMonitorScreen extends StatelessWidget {
  const LiveMonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        const TopBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              // Top three panels
              Expanded(
                flex: 6,
                child: Row(children: [
                  Expanded(child: const MotionTrackingPanel()),
                  const SizedBox(width: 8),
                  Expanded(child: const PlantarPressurePanel()),
                  const SizedBox(width: 8),
                  Expanded(child: const EEGPanel()),
                ]),
              ),
              const SizedBox(height: 8),
              // Bottom fusion panel
              SizedBox(
                height: 160,
                child: const FusionPanel(),
              ),
            ]),
          ),
        ),
        // Status bar
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: const Color(0xFF060F22),
          child: Row(children: [
            _StatusItem(Icons.schedule, _systemTime()),
            const Spacer(),
            _StatusItem(Icons.videocam_outlined, 'Camera: 60 fps'),
            const SizedBox(width: 24),
            _StatusItem(Icons.accessibility, 'Pressure: 100 Hz'),
            const SizedBox(width: 24),
            _StatusItem(Icons.psychology_outlined, 'EEG: 250 Hz'),
            const Spacer(),
            _StatusItem(Icons.info_outline, 'Research Use Only'),
            const SizedBox(width: 8),
            _StatusItem(Icons.circle, 'v2.1.0'),
          ]),
        ),
      ]),
    );
  }

  String _systemTime() {
    final now = DateTime.now();
    return 'System Time: ${now.year}-${_p(now.month)}-${_p(now.day)} '
           '${_p(now.hour)}:${_p(now.minute)}:${_p(now.second)}';
  }
  String _p(int v) => v.toString().padLeft(2, '0');
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _StatusItem(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 10, color: AppColors.textSecondary),
    const SizedBox(width: 4),
    Text(text, style: const TextStyle(
      color: AppColors.textSecondary, fontSize: 9,
    )),
  ]);
}
