import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/features/chats/utils/video_codec_helper.dart';

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

      // Пытаемся получить совместимый путь к видео (с конвертацией HEVC в H.264 при необходимости)
      String? playablePath = await VideoCodecHelper.getPlayableVideoPath(widget.videoPath);
      if (playablePath == null) {
        playablePath = widget.videoPath; // Fallback к оригиналу
      }

      _controller = VideoPlayerController.file(File(playablePath));
      await _controller!.initialize();
      await _controller!.setLooping(true);
      await _controller!.setVolume(0);
      await _controller!.play();

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
      // Try to handle codec incompatibility by checking if it's an HEVC issue
      final errorMessage = e.toString();
      if (errorMessage.contains('MediaCodec') || errorMessage.contains('hevc') || errorMessage.contains('hvc1')) {
        debugPrint('HEVC codec not supported, attempting conversion...');
        // Пробуем конвертацию при ошибке
        final convertedPath = await VideoCodecHelper.convertHevcToH264(widget.videoPath);
        if (convertedPath != null && mounted) {
          debugPrint('Retrying with converted file: $convertedPath');
          // Рекурсивно пробуем с конвертированным файлом
          await _initializeWithConvertedFile(convertedPath);
          return;
        }
      }
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  Future<void> _initializeWithConvertedFile(String convertedPath) async {
    try {
      _controller = VideoPlayerController.file(File(convertedPath));
      await _controller!.initialize();
      await _controller!.setLooping(true);
      await _controller!.setVolume(0);
      await _controller!.play();

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
      debugPrint('Failed to initialize with converted file: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  Future<void> _openFullscreen() async {
    final c = _controller;
    if (c == null || !_isInitialized || _hasError) return;

    final pos = c.value.position;
    await c.pause();
    await c.setVolume(1);
    if (pos != Duration.zero) {
      try {
        await c.seekTo(pos);
      } catch (_) {}
    }
    await c.play();

    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: const Color(0x01FFFFFF),
        pageBuilder: (context, animation, secondaryAnimation) {
          return _SquareVideoFullscreen(
            heroTag: widget.videoPath,
            controller: c,
            animation: animation,
          );
        },
      ),
    );

    if (!mounted) return;
    try {
      await c.setVolume(0);
      await c.play();
    } catch (_) {}
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
              onTap: _openFullscreen,
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
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedAlert01,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                            size: 48,
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
                        Hero(
                          tag: widget.videoPath,
                          flightShuttleBuilder: (
                            BuildContext flightContext,
                            Animation<double> animation,
                            HeroFlightDirection flightDirection,
                            BuildContext fromHeroContext,
                            BuildContext toHeroContext,
                          ) {
                            // Во время обратной анимации показываем snapshot
                            if (flightDirection == HeroFlightDirection.pop) {
                              return _VideoSnapshot(
                                controller: _controller!,
                                size: size,
                              );
                            }
                            // При открытии используем обычный виджет
                            return toHeroContext.widget;
                          },
                          child: SizedBox.expand(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _controller!.value.size.width,
                                height: _controller!.value.size.height,
                                child: VideoPlayer(_controller!),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: size,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 2),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.timeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.05,
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Виджет для отображения снимка видео во время анимации
class _VideoSnapshot extends StatelessWidget {
  final VideoPlayerController controller;
  final double size;

  const _VideoSnapshot({
    required this.controller,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: size,
        color: Colors.black,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}

class _SquareVideoFullscreen extends StatefulWidget {
  final Object heroTag;
  final VideoPlayerController controller;
  final Animation<double> animation;

  const _SquareVideoFullscreen({
    required this.heroTag,
    required this.controller,
    required this.animation,
  });

  @override
  State<_SquareVideoFullscreen> createState() => _SquareVideoFullscreenState();
}

class _SquareVideoFullscreenState extends State<_SquareVideoFullscreen> {
  VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_c.value.isPlaying) {
        await _c.pause();
      } else {
        await _c.play();
      }
    } catch (_) {}
  }

  Future<void> _seekToFraction(double t) async {
    final d = _c.value.duration;
    if (d == Duration.zero) return;
    final target = Duration(milliseconds: (d.inMilliseconds * t.clamp(0.0, 1.0)).round());
    try {
      await _c.seekTo(target);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final side = (mq.size.shortestSide * 0.86).clamp(240.0, 520.0);
    final theme = Theme.of(context);

    final contentAnim = CurvedAnimation(parent: widget.animation, curve: Curves.easeOut);

    final durMs = _c.value.duration.inMilliseconds;
    final posMs = _c.value.position.inMilliseconds;
    final progress = (durMs > 0) ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    color: theme.colorScheme.surface.withOpacity(0.32),
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: contentAnim,
              child: Center(
                child: Hero(
                  tag: widget.heroTag,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _c.value.size.width,
                          height: _c.value.size.height,
                          child: VideoPlayer(_c),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: FadeTransition(
                opacity: contentAnim,
                child: Center(
                  child: GlassSurface(
                    borderRadius: 999,
                    blurSigma: 12,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: SizedBox(
                      width: side,
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: _toggle,
                            child: GlassSurface(
                              borderRadius: 12,
                              blurSigma: 12,
                              width: 32,
                              height: 32,
                              child: Center(
                                child: HugeIcon(
                                  icon: _c.value.isPlaying ? HugeIcons.strokeRoundedStop : HugeIcons.strokeRoundedPlay,
                                  size: 18,
                                  color: theme.colorScheme.onSurface.withOpacity(0.9),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final w = constraints.maxWidth;
                                void seekFromX(double dx) {
                                  final x = dx.clamp(0.0, w);
                                  _seekToFraction(x / w);
                                }

                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (d) => seekFromX(d.localPosition.dx),
                                  onHorizontalDragStart: (d) => seekFromX(d.localPosition.dx),
                                  onHorizontalDragUpdate: (d) => seekFromX(d.localPosition.dx),
                                  child: SizedBox(
                                    height: 22,
                                    child: Center(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(999),
                                        child: Container(
                                          height: 4,
                                          color: theme.colorScheme.onSurface.withOpacity(
                                            theme.brightness == Brightness.dark ? 0.18 : 0.12,
                                          ),
                                          alignment: Alignment.centerLeft,
                                          child: FractionallySizedBox(
                                            widthFactor: progress,
                                            child: Container(
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}