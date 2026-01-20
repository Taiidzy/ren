import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:ren/shared/widgets/glass_surface.dart';

class SquareVideoBubble extends StatefulWidget {
  final String videoPath;
  final String timeLabel;
  final bool isMe;
  final bool isDark;

  const SquareVideoBubble({
    super.key,
    required this.videoPath,
    required this.timeLabel,
    required this.isMe,
    required this.isDark,
  });

  @override
  State<SquareVideoBubble> createState() => _SquareVideoBubbleState();
}

class _SquareVideoBubbleState extends State<SquareVideoBubble> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
        return;
      }

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();

      _controller!.addListener(() {
        if (mounted) {
          final isPlaying = _controller!.value.isPlaying;
          if (isPlaying != _isPlaying) {
            setState(() {
              _isPlaying = isPlaying;
            });
          }
        }
      });

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Failed to initialize video player: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_controller == null || !_isInitialized) return;

    try {
      if (_isPlaying) {
        await _controller!.pause();
      } else {
        await _controller!.play();
      }
    } catch (e) {
      debugPrint('Failed to toggle playback: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseInk = widget.isDark ? Colors.white : Colors.black;
    final isMeColor = widget.isMe
        ? (widget.isDark
            ? theme.colorScheme.primary.withOpacity(0.35)
            : theme.colorScheme.primary.withOpacity(0.22))
        : null;

    const size = 220.0;

    return GlassSurface(
      borderRadius: 16,
      blurSigma: 12,
      color: isMeColor,
      borderColor: baseInk.withOpacity(widget.isDark ? 0.20 : 0.10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: size),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _togglePlayback,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: size,
                  height: size,
                  color: theme.colorScheme.surface,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_hasError)
                        Center(
                          child: Icon(
                            Icons.error_outline,
                            size: 48,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        )
                      else if (!_isInitialized)
                        Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        )
                      else if (_controller != null)
                        SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _controller!.value.size.width,
                              height: _controller!.value.size.height,
                              child: VideoPlayer(_controller!),
                            ),
                          ),
                        ),
                      if (_isInitialized && !_hasError)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.timeLabel,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
