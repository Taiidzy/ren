import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:ren/features/chats/presentation/widgets/chat_attach_menu.dart';
import 'package:ren/features/chats/presentation/widgets/chat_pending_attachment.dart';
import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/features/chats/presentation/widgets/chat_recorder_ui.dart';

class ChatInputBar extends StatefulWidget {
  
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final bool isEditing;
  final VoidCallback onCancelEditing;
  final bool hasReply;
  final String replyText;
  final VoidCallback onCancelReply;
  final List<PendingChatAttachment> pending;
  final void Function(int index) onRemovePending;
  final Future<void> Function() onPickPhotos;
  final Future<void> Function() onPickFiles;
  final Future<void> Function() onTakePhoto;
  final VoidCallback onSend;
  final void Function(RecorderMode mode, bool isRecording)? onRecordingChanged;
  final void Function(String durationText)? onRecordingDurationChanged;
  final void Function(RecorderMode mode, bool isLocked)? onRecordingLockedChanged;
  final void Function(VoidCallback cancel, VoidCallback stop)? onRecorderController;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.isEditing,
    required this.onCancelEditing,
    required this.hasReply,
    required this.replyText,
    required this.onCancelReply,
    required this.pending,
    required this.onRemovePending,
    required this.onPickPhotos,
    required this.onPickFiles,
    required this.onTakePhoto,
    required this.onSend,
    this.onRecordingChanged,
    this.onRecordingDurationChanged,
    this.onRecordingLockedChanged,
    this.onRecorderController,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {

  final GlobalKey<ChatRecorderButtonState> _recorderKey =
      GlobalKey<ChatRecorderButtonState>();


  RecorderMode _activeRecordingMode = RecorderMode.audio;


  bool _isRecording = false;
  bool _isRecordingLocked = false;
  String _durationText = "0:00";
  Timer? _timer;
  int _seconds = 0;

  // Слушатель для кнопки Send/Mic
  bool get _showSendButton => widget.controller.text.trim().isNotEmpty || widget.pending.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRecorderController?.call(
        () => _recorderKey.currentState?.cancelRecording(),
        () => _recorderKey.currentState?.stopRecording(),
      );
    });
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRecorderController?.call(
        () => _recorderKey.currentState?.cancelRecording(),
        () => _recorderKey.currentState?.stopRecording(),
      );
    });
  }

  void _startTimer() {
    _seconds = 0;
    _durationText = "0:00";
    widget.onRecordingDurationChanged?.call(_durationText);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _seconds++;
      if (_activeRecordingMode == RecorderMode.video && _seconds >= 60) {
        _recorderKey.currentState?.stopRecording();
        return;
      }
      final m = (_seconds ~/ 60).toString();
      final s = (_seconds % 60).toString().padLeft(2, '0');
      if (mounted) {
        setState(() {
          _durationText = "$m:$s";
        });
      }
      widget.onRecordingDurationChanged?.call(_durationText);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  void _resetRecordingUi() {
    _isRecording = false;
    _isRecordingLocked = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const double inputHeight = 44;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isRecording) ...[
             if (widget.isEditing)
               Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassSurface(
                  borderRadius: 16,
                  blurSigma: 10,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Редактирование',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: widget.onCancelEditing,
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: theme.colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
             if (widget.hasReply)
               AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      axisAlignment: -1,
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  key: ValueKey<String>('reply_${widget.replyText.trim()}'),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassSurface(
                    borderRadius: 16,
                    blurSigma: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.reply,
                          size: 16,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.replyText.trim().isNotEmpty ? widget.replyText.trim() : 'Сообщение',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(0.9),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: widget.onCancelReply,
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
             if (widget.pending.isNotEmpty)
              Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.pending.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final p = widget.pending[index];
                    final isImg = p.mimetype.startsWith('image/');
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 64,
                            height: 64,
                            color: theme.colorScheme.surface,
                            child: isImg
                                ? Image.memory(
                                    p.bytes,
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => const SizedBox(),
                                  )
                                : Center(
                                    child: Icon(
                                      Icons.insert_drive_file,
                                      color: theme.colorScheme.onSurface.withOpacity(0.65),
                                    ),
                                  ),
                          ),
                        ),
                        Positioned(
                          right: -6,
                          top: -6,
                          child: GestureDetector(
                            onTap: () => widget.onRemovePending(index),
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.onSurface.withOpacity(0.25),
                                ),
                              ),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: theme.colorScheme.onSurface.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
            
          Row(
            children: [
              if (!_isRecording)
              GlassSurface(
                borderRadius: 18,
                blurSigma: 12,
                width: inputHeight,
                height: inputHeight,
                onTap: () => showChatAttachMenu(
                  context,
                  onPickPhotos: () async => await widget.onPickPhotos(),
                  onPickFiles: () async => await widget.onPickFiles(),
                  onTakePhoto: () async => await widget.onTakePhoto(),
                ),
                child: Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedAttachment01,
                    color: theme.colorScheme.onSurface.withOpacity(0.9),
                    size: 18,
                  ),
                ),
              ),
              if (!_isRecording) const SizedBox(width: 10),
              Expanded(
                child: GlassSurface(
                  borderRadius: 18,
                  blurSigma: 12,
                  height: inputHeight,
                  borderColor: theme.colorScheme.onSurface.withOpacity(widget.isDark ? 0.20 : 0.10),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: animation,
                          axisAlignment: -1,
                          child: child,
                        ),
                      );
                    },
                    child: _isRecording
                        ? Padding(
                            key: const ValueKey('recording_ui'),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _durationText,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                if (_isRecordingLocked) ...[
                                  Text(
                                    'Отмена',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withOpacity(0.75),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  GlassSurface(
                                    borderRadius: 18,
                                    blurSigma: 12,
                                    width: 32,
                                    height: 32,
                                    onTap: () {
                                      _recorderKey.currentState?.cancelRecording();
                                    },
                                    child: Center(
                                      child: Icon(
                                        Icons.close,
                                        size: 16,
                                        color: theme.colorScheme.onSurface.withOpacity(0.85),
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  ShimmerText(
                                    text: '< Свайп для отмены',
                                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                  const SizedBox(width: 20),
                                ],
                              ],
                            ),
                          )
                        : TextField(
                            key: const ValueKey('input_field'),
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 14,
                            ),
                            cursorColor: theme.colorScheme.primary,
                            decoration: InputDecoration(
                              hintText: 'Введите сообщение...',
                              hintStyle: TextStyle(
                                color: theme.colorScheme.onSurface.withOpacity(0.55),
                              ),
                              filled: false,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                            ),
                          ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Кнопка записи / Отправки
              ChatRecorderButton(
                key: _recorderKey,
                showSendButton: _showSendButton,
                onSendText: widget.onSend,
                onStartRecording: (mode) async {
                  // Здесь вызываем проверку прав и старт записи
                  // TODO: Реализовать permission request
                  setState(() {
                    _isRecording = true;
                    _isRecordingLocked = false;
                  });
                  _activeRecordingMode = mode;
                  widget.onRecordingChanged?.call(mode, true);
                  widget.onRecordingLockedChanged?.call(mode, false);
                  _startTimer();
                  return true; 
                },
                onStopRecording: (mode, path, canceled) {
                  setState(() {
                    _resetRecordingUi();
                  });
                  _stopTimer();
                  widget.onRecordingChanged?.call(mode, false);
                  widget.onRecordingLockedChanged?.call(mode, false);
                  if (!canceled) {
                    // TODO: Отправить файл (path)
                    debugPrint("Send $mode message");
                  }
                },
                onCancelRecording: () {
                  setState(() {
                    _resetRecordingUi();
                  });
                  _stopTimer();
                  widget.onRecordingChanged?.call(_activeRecordingMode, false);
                  widget.onRecordingLockedChanged?.call(_activeRecordingMode, false);
                },
                onLockRecording: () {
                  if (!mounted) return;
                  setState(() {
                    _isRecordingLocked = true;
                  });
                  widget.onRecordingLockedChanged?.call(_activeRecordingMode, true);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Простой виджет для мерцающего текста (Slide to cancel)
class ShimmerText extends StatefulWidget {
  final String text;
  final Color color;
  const ShimmerText({super.key, required this.text, required this.color});

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.5 + 0.5 * math.sin(_controller.value * 2 * math.pi).abs(),
          child: Text(widget.text, style: TextStyle(color: widget.color)),
        );
      },
    );
  }
}