import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Renders an uploaded exercise-guide clip, looping: animated images (GIF /
/// WebP / APNG) via [Image.file], real video (MP4 / MOV / WebM …) via media_kit
/// (libmpv, desktop-capable) — muted, no controls. One widget so every guide
/// surface (library, protocol builder, participant view) handles both.
class ExerciseMediaView extends StatefulWidget {
  final String path;
  final BoxFit fit;
  const ExerciseMediaView(this.path, {super.key, this.fit = BoxFit.contain});

  static const _imageExt = {'gif', 'webp', 'apng', 'png', 'jpg', 'jpeg'};
  static const _videoExt = {'mp4', 'mov', 'webm', 'mkv', 'avi', 'm4v'};

  static String _ext(String p) =>
      p.contains('.') ? p.split('.').last.toLowerCase() : '';
  static bool isImage(String p) => _imageExt.contains(_ext(p));
  static bool isVideo(String p) => _videoExt.contains(_ext(p));
  static bool isSupported(String p) => isImage(p) || isVideo(p);

  /// Extensions offered in the upload picker (images that loop + playable video).
  static List<String> get pickerExtensions =>
      [..._imageExt.where((e) => e != 'png' && e != 'jpg' && e != 'jpeg'), ..._videoExt];

  @override
  State<ExerciseMediaView> createState() => _ExerciseMediaViewState();
}

class _ExerciseMediaViewState extends State<ExerciseMediaView> {
  Player? _player;
  VideoController? _controller;

  @override
  void initState() {
    super.initState();
    if (ExerciseMediaView.isVideo(widget.path)) _initVideo();
  }

  void _initVideo() {
    final p = Player();
    _player = p;
    _controller = VideoController(p);
    p.setPlaylistMode(PlaylistMode.loop);
    p.setVolume(0);
    // A file:// URI is the most portable way to hand a local path to libmpv.
    p.open(Media(Uri.file(widget.path).toString()), play: true);
  }

  @override
  void didUpdateWidget(covariant ExerciseMediaView old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _disposePlayer();
      if (ExerciseMediaView.isVideo(widget.path)) _initVideo();
      setState(() {});
    }
  }

  void _disposePlayer() {
    _controller = null;
    _player?.dispose();
    _player = null;
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    if (ExerciseMediaView.isImage(path)) {
      return Image.file(
        File(path),
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _unavailable(),
      );
    }
    if (_controller != null) {
      return Video(
        controller: _controller!,
        fit: widget.fit,
        controls: NoVideoControls,
      );
    }
    return _unavailable();
  }

  Widget _unavailable() => const Center(
        child: Text('Media unavailable',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      );
}
