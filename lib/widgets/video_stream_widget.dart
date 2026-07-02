import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/mjpeg_stream.dart';
import '../theme/app_theme.dart';

/// Displays a live MJPEG stream from [url].
/// Shows a labelled placeholder with a pulsing indicator until the first frame.
class VideoStreamWidget extends StatefulWidget {
  final String url;
  final String label;
  final BoxFit fit;

  const VideoStreamWidget({
    super.key,
    required this.url,
    required this.label,
    this.fit = BoxFit.contain,
  });

  @override
  State<VideoStreamWidget> createState() => _VideoStreamWidgetState();
}

class _VideoStreamWidgetState extends State<VideoStreamWidget> {
  late MjpegStream _stream;
  Uint8List? _frame;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _stream = MjpegStream(widget.url);
    _stream.stream.listen(
      (frame) {
        if (mounted) setState(() { _frame = frame; _hasError = false; });
      },
      onError: (_) {
        if (mounted) setState(() => _hasError = true);
      },
    );
  }

  @override
  void dispose() {
    _stream.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      // Video frame
      if (_frame != null)
        Image.memory(
          _frame!,
          fit: widget.fit,
          gaplessPlayback: true,   // prevents flicker between frames
        )
      else
        _Placeholder(label: widget.label, hasError: _hasError),

      // Label overlay
      Positioned(
        bottom: 6, left: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6, height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _frame != null ? AppColors.accentGreen : AppColors.inkMuted,
              ),
            ),
            Text(widget.label, style: GoogleFonts.schibstedGrotesk(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500,
            )),
          ]),
        ),
      ),
    ]);
  }
}

class _Placeholder extends StatelessWidget {
  final String label;
  final bool hasError;
  const _Placeholder({required this.label, required this.hasError});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF060F22),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (hasError) ...[
          const Icon(Icons.videocam_off_outlined,
              color: AppColors.inkMuted, size: 28),
          const SizedBox(height: 8),
          Text('No signal', style: GoogleFonts.schibstedGrotesk(
            color: AppColors.inkMuted, fontSize: 11,
          )),
          Text('Start Unity to see video', style: GoogleFonts.schibstedGrotesk(
            color: AppColors.inkMuted, fontSize: 9,
          )),
        ] else ...[
          const SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text('Connecting to $label…', style: GoogleFonts.schibstedGrotesk(
            color: AppColors.inkMuted, fontSize: 10,
          )),
        ],
      ]),
    ).animate(onPlay: (c) => c.repeat())
     .shimmer(duration: 2.seconds, color: AppColors.inkBorder.withOpacity(0.3));
  }
}
