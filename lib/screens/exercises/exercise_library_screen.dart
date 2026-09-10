import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/exercise_asset.dart';
import '../../services/exercise_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_guide_player.dart';
import '../../widgets/exercise_media_view.dart';
import 'exercise_record_screen.dart';

/// Library of authored exercises. Each exercise is a reusable reference movement
/// — a recorded skeleton-avatar clip (or an uploaded media file) — that a
/// protocol block shows the participant as its guide.
class ExerciseLibraryScreen extends StatelessWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ExerciseRepository>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _header(context, repo),
            const SizedBox(height: 20),
            Expanded(
              child: repo.exercises.isEmpty
                  ? _empty(context, repo)
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final e in repo.exercises)
                            _ExerciseCard(exercise: e, repo: repo),
                        ],
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ExerciseRepository repo) => Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('exercise library', style: AppTheme.eyebrow()),
            Text('Exercises',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800)),
          ]),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => _uploadMedia(context, repo),
            icon: const Icon(Icons.gif_box_outlined, size: 18),
            label: const Text('Upload media'),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => _importFromRecording(context, repo),
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Import recording'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () => _recordNew(context),
            icon: const Icon(Icons.videocam, size: 18),
            label: const Text('Record with ZED'),
          ),
        ],
      );

  Widget _empty(BuildContext context, ExerciseRepository repo) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.directions_run_outlined,
              size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text('No exercises yet',
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Create an exercise from a recorded movement. It plays back on the '
              'avatar and can be used as a block guide in the protocol builder. '
              '(Recording directly with the ZED is coming next.)',
              textAlign: TextAlign.center,
              style: GoogleFonts.schibstedGrotesk(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 20),
          Row(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton.icon(
              onPressed: () => _uploadMedia(context, repo),
              icon: const Icon(Icons.gif_box_outlined, size: 18),
              label: const Text('Upload media'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _recordNew(context),
              icon: const Icon(Icons.videocam, size: 18),
              label: const Text('Record with ZED'),
            ),
          ]),
        ]),
      );

  /// Prompt for a name, then record a demonstration with the ZED.
  Future<void> _recordNew(BuildContext context) async {
    final name = await _promptName(context);
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExerciseRecordScreen(name: name.trim()),
    ));
  }

  /// Import a recorded `zed_skeleton.json` (from a session or an authoring
  /// capture) as a new avatar exercise.
  Future<void> _importFromRecording(
      BuildContext context, ExerciseRepository repo) async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a recorded zed_skeleton.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = res?.files.single.path;
    if (path == null || !context.mounted) return;
    final name = await _promptName(context);
    if (name == null || name.trim().isEmpty) return;
    try {
      await repo.importFromSkeletonJson(name.trim(), path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  /// Upload a GIF / WebP / video clip as a reusable "media" exercise guide.
  Future<void> _uploadMedia(
      BuildContext context, ExerciseRepository repo) async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a GIF, WebP or video clip',
      type: FileType.custom,
      allowedExtensions: ExerciseMediaView.pickerExtensions,
    );
    final path = res?.files.single.path;
    if (path == null || !context.mounted) return;
    final name = await _promptName(context);
    if (name == null || name.trim().isEmpty) return;
    try {
      await repo.importMedia(name.trim(), path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  Future<String?> _promptName(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this exercise'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Seated knee extension'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('Create')),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final ExerciseAsset exercise;
  final ExerciseRepository repo;
  const _ExerciseCard({required this.exercise, required this.repo});

  @override
  Widget build(BuildContext context) {
    final secs = (exercise.durationMs / 1000).toStringAsFixed(1);
    return SizedBox(
      width: 264,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => _preview(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(exercise.isRecorded ? Icons.animation : Icons.gif_box_outlined,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(exercise.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.schibstedGrotesk(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDelete(context),
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: AppColors.textSecondary),
                  tooltip: 'Delete',
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                exercise.isRecorded
                    ? 'Avatar · ${exercise.frameCount} frames · ${secs}s'
                    : 'Uploaded media',
                style: GoogleFonts.schibstedGrotesk(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _preview(context),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Preview'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _preview(BuildContext context) async {
    final frames = await repo.loadFrames(exercise);
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.inkBg,
        child: SizedBox(
          width: 460,
          height: 480,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(children: [
                Expanded(
                  child: Text(exercise.name,
                      style: GoogleFonts.schibstedGrotesk(
                          color: AppColors.inkText,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close, color: AppColors.inkMuted),
                ),
              ]),
            ),
            Expanded(child: AvatarGuidePlayer(frames: frames)),
          ]),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete exercise?'),
        content: Text('“${exercise.name}” will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await repo.delete(exercise.id);
  }
}
