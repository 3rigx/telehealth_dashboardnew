import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/skeleton_3d.dart';
import '../../services/app_settings.dart';
import '../../services/exercise_record_controller.dart';
import '../../services/exercise_repository.dart';
import '../../services/unity_connection_service.dart';
import '../../services/unity_launch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sensor_warmup_loader.dart';
import '../../widgets/skeleton_3d_view.dart';

/// Record an exercise demonstration with the ZED. The clinician performs the
/// movement a few times; on Stop it's imported as an avatar exercise.
class ExerciseRecordScreen extends StatefulWidget {
  final String name;
  const ExerciseRecordScreen({super.key, required this.name});

  @override
  State<ExerciseRecordScreen> createState() => _ExerciseRecordScreenState();
}

class _ExerciseRecordScreenState extends State<ExerciseRecordScreen> {
  late final ExerciseRecordController _ctrl;
  late final UnityConnectionService _conn;

  @override
  void initState() {
    super.initState();
    _conn = context.read<UnityConnectionService>();
    _ctrl = ExerciseRecordController(
      conn: _conn,
      settings: context.read<AppSettings>(),
      exercises: context.read<ExerciseRepository>(),
      name: widget.name,
      launcher: context.read<UnityLaunchService>(),
    )..addListener(_onChange);
    _conn.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.prepare());
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _conn.removeListener(_onChange);
    _ctrl.removeListener(_onChange);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05080F),
      body: SafeArea(child: _content()),
    );
  }

  Widget _content() {
    switch (_ctrl.stage) {
      case RecordStage.connecting:
      case RecordStage.preparing:
        return SensorWarmupLoader(
            title: 'Warming up the camera',
            message: _ctrl.message.isEmpty ? null : _ctrl.message);
      case RecordStage.ready:
      case RecordStage.recording:
        return _capture();
      case RecordStage.saving:
        return _stageOverlay(null, _ctrl.message.isEmpty ? 'Saving…' : _ctrl.message);
      case RecordStage.done:
        return _doneView();
      case RecordStage.error:
        return _errorView(_ctrl.message);
      case RecordStage.idle:
        return _stageOverlay(null, 'Preparing…');
    }
  }

  Widget _capture() {
    final recording = _ctrl.stage == RecordStage.recording;
    final sk = _conn.state.skeleton ?? Skeleton3D.seatedDemo(kneeAngleDeg: 50);
    final secs = (_ctrl.elapsedMs / 1000).toStringAsFixed(1);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.inkMuted),
            tooltip: 'Cancel',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(widget.name,
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.inkText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ),
          if (recording)
            Row(children: [
              const _RecDot(),
              const SizedBox(width: 8),
              Text('${secs}s',
                  style: GoogleFonts.schibstedGrotesk(
                      color: AppColors.accentRed,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ]),
        ]),
      ),
      Expanded(child: Skeleton3DView(skeleton: sk)),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: Column(children: [
          Text(
            recording
                ? 'Perform the movement a few clear times, then Stop.'
                : _ctrl.message,
            textAlign: TextAlign.center,
            style: GoogleFonts.schibstedGrotesk(
                color: AppColors.inkMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          if (!recording)
            ElevatedButton.icon(
              onPressed: _ctrl.begin,
              icon: const Icon(Icons.fiber_manual_record, size: 16),
              label: const Text('Record'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
                textStyle: GoogleFonts.schibstedGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _ctrl.stop,
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Stop & save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
                textStyle: GoogleFonts.schibstedGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _doneView() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, size: 64, color: AppColors.accentGreen),
          const SizedBox(height: 16),
          Text('Exercise saved',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.inkText,
                  fontSize: 24,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_ctrl.message,
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.inkMuted, fontSize: 13)),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            ),
            child: const Text('Back to library'),
          ),
        ]),
      );

  Widget _errorView(String msg) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 56, color: AppColors.accentRed),
          const SizedBox(height: 16),
          Text('Could not record',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.inkText,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(msg,
                textAlign: TextAlign.center,
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.inkMuted, fontSize: 13)),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Back'),
          ),
        ]),
      );

  Widget _stageOverlay(IconData? icon, String msg) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon == null)
            const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 3))
          else
            Icon(icon, size: 48, color: AppColors.inkMuted),
          const SizedBox(height: 18),
          Text(msg,
              textAlign: TextAlign.center,
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.inkMuted, fontSize: 15)),
        ]),
      );
}

class _RecDot extends StatefulWidget {
  const _RecDot();
  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
        child: Container(
          width: 11,
          height: 11,
          decoration: const BoxDecoration(
              color: AppColors.accentRed, shape: BoxShape.circle),
        ),
      );
}
