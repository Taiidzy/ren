import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:ren/shared/widgets/glass_surface.dart';

enum RecorderMode { audio, video }
enum RecorderState { idle, recording, locked }

class ChatRecorderButton extends StatefulWidget {
  final bool showSendButton;
  final VoidCallback onSendText;
  
  // Callbacks
  final Future<bool> Function(RecorderMode mode) onStartRecording;
  final Function(RecorderMode mode, String? path, bool isCanceled) onStopRecording;
  final VoidCallback onCancelRecording;
  final VoidCallback onLockRecording;

  const ChatRecorderButton({
    super.key,
    required this.showSendButton,
    required this.onSendText,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancelRecording,
    required this.onLockRecording,
  });

  @override
  State<ChatRecorderButton> createState() => ChatRecorderButtonState();
}

class ChatRecorderButtonState extends State<ChatRecorderButton> with TickerProviderStateMixin {
  RecorderMode _mode = RecorderMode.audio;
  RecorderState _state = RecorderState.idle;

  // Animation Controllers
  late AnimationController _scaleController; // Рост кнопки при нажатии
  late AnimationController _lockController;  // Анимация замка
  
  // Drag logic
  Offset _dragStart = Offset.zero;
  Offset _currentDrag = Offset.zero;
  
  double get _dragOffsetY => _currentDrag.dy - _dragStart.dy;
  double get _dragOffsetX => _currentDrag.dx - _dragStart.dx;

  void cancelRecording() {
    if (_state == RecorderState.idle) return;
    _stopRecording(isCanceled: true);
    widget.onCancelRecording();
  }

  void stopRecording() {
    if (_state == RecorderState.idle) return;
    _stopRecording(isCanceled: false);
  }

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 1.0,
      upperBound: 1.6,
    );
    _lockController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _lockController.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _mode = _mode == RecorderMode.audio ? RecorderMode.video : RecorderMode.audio;
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _onLongPressStart(LongPressStartDetails details) async {
    if (widget.showSendButton) return;

    // Проверка прав перед стартом
    final allowed = await widget.onStartRecording(_mode);
    if (!allowed) return;

    HapticFeedback.mediumImpact();
    
    setState(() {
      _state = RecorderState.recording;
      _dragStart = details.globalPosition;
      _currentDrag = details.globalPosition;
    });

    _scaleController.forward();
    _lockController.repeat(reverse: true); // Анимация "дрыгания" замка
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_state != RecorderState.recording) return;

    setState(() {
      _currentDrag = details.globalPosition;
    });

    // Логика блокировки (свайп вверх)
    if (_dragOffsetY < -100) {
      _lockRecording();
    }

    // Логика отмены (свайп влево)
    if (_dragOffsetX < -150) {
      _cancelRecording();
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_state == RecorderState.recording) {
      _stopRecording(isCanceled: false);
    }
  }

  void _lockRecording() {
    setState(() {
      _state = RecorderState.locked;
    });
    _scaleController.reverse(); // Возвращаем размер кнопки
    _lockController.stop();
    _lockController.value = 0; // Сброс замка
    widget.onLockRecording();
    HapticFeedback.heavyImpact();
  }

  void _cancelRecording() {
    _stopRecording(isCanceled: true);
    widget.onCancelRecording();
    HapticFeedback.heavyImpact();
  }

  void _stopRecording({required bool isCanceled}) {
    _scaleController.reverse();
    _lockController.stop();
    _lockController.value = 0;
    
    widget.onStopRecording(_mode, null, isCanceled);

    setState(() {
      _state = RecorderState.idle;
      _currentDrag = Offset.zero;
      _dragStart = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;
    final isRecording = _state == RecorderState.recording;
    
    // Если есть текст, показываем обычную кнопку отправки
    if (widget.showSendButton) {
      return GestureDetector(
        onTap: widget.onSendText,
        child: GlassSurface(
          borderRadius: 18,
          blurSigma: 12,
          width: 44,
          height: 44,
          color: theme.colorScheme.primary,
          borderColor: baseInk.withOpacity(isDark ? 0.18 : 0.10),
          child: Center(
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedSent,
              color: theme.colorScheme.onPrimary,
              size: 20,
            ),
          ),
        ),
      );
    }

    // Логика трансформации иконки при драге
    double translateX = 0;
    double translateY = 0;

    if (isRecording) {
      // Ограничиваем движение иконки за пальцем
      translateX = _dragOffsetX.clamp(-100.0, 0.0);
      translateY = _dragOffsetY.clamp(-100.0, 0.0);
    }

    final targetOffset = Offset(translateX, translateY);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // LOCK ICON (Выезжает сверху при записи)
        Positioned(
          top: -100 + translateY * 0.5, // Параллакс эффект для замка
          child: AnimatedOpacity(
            opacity: isRecording ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: AnimatedScale(
              scale: isRecording ? 1.0 : 0.96,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: IgnorePointer(
                ignoring: !isRecording,
                child: AnimatedBuilder(
                  animation: _lockController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _lockController.value * -10), // Легкое подпрыгивание
                      child: Opacity(
                        opacity: ((-_dragOffsetY) / 100).clamp(0.0, 1.0),
                        child: GlassSurface(
                          borderRadius: 16,
                          blurSigma: 10,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          color: theme.colorScheme.surface.withOpacity(isDark ? 0.35 : 0.55),
                          borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.14),
                          child: Column(
                            children: [
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedLockKey,
                                color: theme.colorScheme.onSurface.withOpacity(0.9),
                                size: 22,
                              ),
                              const SizedBox(height: 2),
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedArrowUp01,
                                size: 16,
                                color: theme.colorScheme.onSurface.withOpacity(0.75),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        // MAIN BUTTON
        GestureDetector(
          onTap: () {
            if (_state == RecorderState.locked) {
              stopRecording();
            } else {
              _switchMode();
            }
          },
          onLongPressStart: _onLongPressStart,
          onLongPressMoveUpdate: _onLongPressMoveUpdate,
          onLongPressEnd: _onLongPressEnd,
          child: TweenAnimationBuilder<Offset>(
            tween: Tween<Offset>(begin: targetOffset, end: targetOffset),
            duration: const Duration(milliseconds: 70),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Transform.translate(
                offset: value,
                child: child,
              );
            },
            child: AnimatedBuilder(
              animation: _scaleController,
              builder: (context, child) {
                // Если запись идет, кнопка большая. Если заблокировано - кнопка меняется на "Стоп/Отправить"
                double scale = _scaleController.value;
                if (_state == RecorderState.locked) scale = 1.0;

                return Transform.scale(
                  scale: scale,
                  child: GlassSurface(
                    borderRadius: 18,
                    blurSigma: 12,
                    width: 44,
                    height: 44,
                    child: Center(
                      child: _state == RecorderState.locked
                          ? HugeIcon(
                              icon: HugeIcons.strokeRoundedSent,
                              color: theme.colorScheme.onSurface.withOpacity(0.9),
                              size: 20,
                            )
                          : HugeIcon(
                              icon: _mode == RecorderMode.audio
                                  ? HugeIcons.strokeRoundedMic01
                                  : HugeIcons.strokeRoundedVideo01,
                              size: 20,
                              color: isRecording
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}