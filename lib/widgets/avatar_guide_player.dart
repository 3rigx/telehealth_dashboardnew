import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session_models.dart' show SkeletonFrame;
import '../services/exercise_repository.dart';
import 'skeleton_3d_view.dart';

/// Plays a recorded skeleton clip on the bone avatar, looping — the participant's
/// exercise guide. Advances frames on a wall-clock timer scaled to the clip's
/// own duration, so the guide moves at roughly the recorded speed.
class AvatarGuidePlayer extends StatefulWidget {
  final List<SkeletonFrame> frames;
  const AvatarGuidePlayer({super.key, required this.frames});

  @override
  State<AvatarGuidePlayer> createState() => _AvatarGuidePlayerState();
}

class _AvatarGuidePlayerState extends State<AvatarGuidePlayer> {
  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _i = 0;
    final n = widget.frames.length;
    if (n < 2) return;
    // Average frame interval from the clip's own timeline (ZED ≈ 15 Hz),
    // clamped so playback stays smooth and sane.
    final avg = (widget.frames.last.tMs / (n - 1)).round().clamp(33, 120);
    _timer = Timer.periodic(Duration(milliseconds: avg), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % n);
    });
  }

  @override
  void didUpdateWidget(covariant AvatarGuidePlayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.frames, widget.frames)) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.frames.isEmpty) {
      return const Center(
        child: Text('No motion recorded',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
      );
    }
    final frame = widget.frames[_i.clamp(0, widget.frames.length - 1)];
    return Skeleton3DView(skeleton: frame.skeleton);
  }
}

/// Loads an authored exercise's recorded frames (once, by id) and plays them on
/// the avatar — the block guide. Shows a loader while reading and an empty state
/// if the exercise is missing or has no recorded motion.
class AvatarExerciseGuide extends StatefulWidget {
  final String exerciseId;
  const AvatarExerciseGuide({super.key, required this.exerciseId});

  @override
  State<AvatarExerciseGuide> createState() => _AvatarExerciseGuideState();
}

class _AvatarExerciseGuideState extends State<AvatarExerciseGuide> {
  List<SkeletonFrame>? _frames;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AvatarExerciseGuide old) {
    super.didUpdateWidget(old);
    if (old.exerciseId != widget.exerciseId) {
      _frames = null;
      _load();
    }
  }

  Future<void> _load() async {
    final repo = context.read<ExerciseRepository>();
    final ex = repo.byId(widget.exerciseId);
    final frames = ex == null ? <SkeletonFrame>[] : await repo.loadFrames(ex);
    if (mounted) setState(() => _frames = frames);
  }

  @override
  Widget build(BuildContext context) {
    if (_frames == null) {
      return const Center(
        child: SizedBox(
            width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    return AvatarGuidePlayer(frames: _frames!);
  }
}
