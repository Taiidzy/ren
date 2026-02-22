import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:ren/shared/widgets/glass_surface.dart';

class VoiceMessageBubble extends StatefulWidget {
  final String audioPath;
  final String timeLabel;
  final bool isMe;
  final bool isDelivered;
  final bool isRead;
  final bool isPending;
  final bool isDark;

  const VoiceMessageBubble({
    super.key,
    required this.audioPath,
    required this.timeLabel,
    required this.isMe,
    this.isDelivered = false,
    this.isRead = false,
    this.isPending = false,
    required this.isDark,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  late final List<double> _waveform;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _waveform = _buildWaveform(seed: widget.audioPath.hashCode);
    _initPlayer();
  }

  List<double> _buildWaveform({required int seed}) {
    final rng = Random(seed);
    return List<double>.generate(38, (_) {
      final v = rng.nextDouble();
      return 0.18 + 0.82 * (v * v);
    });
  }

  Future<void> _initPlayer() async {
    try {
      final file = File(widget.audioPath);
      if (!await file.exists()) {
        debugPrint('Audio file does not exist: ${widget.audioPath}');
        return;
      }

      await _audioPlayer.setFilePath(widget.audioPath);

      _durationSubscription = _audioPlayer.durationStream.listen((duration) {
        if (mounted) {
          setState(() {
            _duration = duration ?? Duration.zero;
          });
        }
      });

      _positionSubscription = _audioPlayer.positionStream.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });

      _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
            _isLoading =
                state.processingState == ProcessingState.loading ||
                state.processingState == ProcessingState.buffering;
          });

          if (state.processingState == ProcessingState.completed) {
            _audioPlayer.pause();
            _audioPlayer.seek(Duration.zero);
            if (mounted) {
              setState(() {
                _isPlaying = false;
                _position = Duration.zero;
              });
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Failed to initialize audio player: $e');
    }
  }

  Future<void> _togglePlayback() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
    } catch (e) {
      debugPrint('Failed to toggle playback: $e');
    }
  }

  Future<void> _seekTo(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      debugPrint('Failed to seek: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseInk = widget.isDark ? Colors.white : Colors.black;
    final mediaW = MediaQuery.sizeOf(context).width;
    final bubbleMaxWidth = (mediaW * 0.68).clamp(220.0, 280.0).toDouble();
    final isMeColor = widget.isMe
        ? (widget.isDark
              ? theme.colorScheme.primary.withOpacity(0.35)
              : theme.colorScheme.primary.withOpacity(0.22))
        : null;

    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return GlassSurface(
      borderRadius: 16,
      blurSigma: 12,
      color: isMeColor,
      borderColor: baseInk.withOpacity(widget.isDark ? 0.20 : 0.10),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _isLoading ? null : _togglePlayback,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.primary,
                                ),
                              ),
                            )
                          : GlassSurface(
                              borderRadius: 12,
                              blurSigma: 12,
                              width: 32,
                              height: 32,
                              child: Center(
                                child: HugeIcon(
                                  icon: _isPlaying
                                      ? HugeIcons.strokeRoundedStop
                                      : HugeIcons.strokeRoundedPlay,
                                  size: 18,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.9),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            return GestureDetector(
                              onTapDown: (details) {
                                if (_duration.inMilliseconds <= 0) return;
                                final localX = details.localPosition.dx.clamp(
                                  0.0,
                                  w,
                                );
                                final seekPosition = Duration(
                                  milliseconds:
                                      ((localX / w) * _duration.inMilliseconds)
                                          .round(),
                                );
                                _seekTo(seekPosition);
                              },
                              child: SizedBox(
                                height: 22,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: List.generate(_waveform.length, (
                                    i,
                                  ) {
                                    final t = (i + 1) / _waveform.length;
                                    final played = t <= progress;
                                    final h = 6 + 14 * _waveform[i];
                                    return Expanded(
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 120,
                                          ),
                                          width: 2.2,
                                          height: h,
                                          decoration: BoxDecoration(
                                            color: played
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.onSurface
                                                      .withOpacity(
                                                        widget.isDark
                                                            ? 0.20
                                                            : 0.14,
                                                      ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(_position),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.7,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _formatDuration(_duration),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.7,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.timeLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                  if (widget.isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      widget.isPending
                          ? Icons.schedule_rounded
                          : (widget.isRead || widget.isDelivered
                                ? Icons.done_all_rounded
                                : Icons.done_rounded),
                      size: 13,
                      color: widget.isPending
                          ? theme.colorScheme.onSurface.withOpacity(0.55)
                          : (widget.isRead
                                ? theme.colorScheme.primary.withOpacity(0.92)
                                : (widget.isDelivered
                                      ? theme.colorScheme.onSurface.withOpacity(
                                          0.65,
                                        )
                                      : theme.colorScheme.onSurface.withOpacity(
                                          0.55,
                                        ))),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
