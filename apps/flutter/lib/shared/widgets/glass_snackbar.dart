import 'dart:async'; // Обязательно для таймера
import 'package:flutter/material.dart';
import 'package:ren/shared/widgets/glass_surface.dart'; //

enum GlassSnackKind { info, success, error }

void showGlassSnack(
  BuildContext context,
  String message, {
  GlassSnackKind kind = GlassSnackKind.info,
  Duration duration = const Duration(seconds: 3),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.clearSnackBars();

  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  final Color accent;
  switch (kind) {
    case GlassSnackKind.success:
      accent = cs.primary;
      break;
    case GlassSnackKind.error:
      accent = cs.error;
      break;
    case GlassSnackKind.info:
      accent = cs.secondary;
      break;
  }

  messenger.showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      // ХИТРОСТЬ: Ставим длительность самого SnackBar больше, чем длительность показа,
      // чтобы мы успели проиграть анимацию исчезновения до того, как Flutter убьет виджет.
      // Реальным временем показа управляет наш _AnimatedGlassSnackContent через таймер.
      duration: duration + const Duration(seconds: 1), 
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      content: _AnimatedGlassSnackContent(
        message: message,
        accent: accent,
        actionLabel: actionLabel,
        onAction: onAction,
        displayDuration: duration, // Передаем желаемое время показа
        onClose: () => messenger.hideCurrentSnackBar(),
      ),
    ),
  );
}

class _AnimatedGlassSnackContent extends StatefulWidget {
  final String message;
  final Color accent;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClose;
  final Duration displayDuration;

  const _AnimatedGlassSnackContent({
    required this.message,
    required this.accent,
    this.actionLabel,
    this.onAction,
    required this.onClose,
    required this.displayDuration,
  });

  @override
  State<_AnimatedGlassSnackContent> createState() =>
      _AnimatedGlassSnackContentState();
}

class _AnimatedGlassSnackContentState extends State<_AnimatedGlassSnackContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600), // Длительность входа
      reverseDuration: const Duration(milliseconds: 400), // Длительность выхода (побыстрее)
    );

    // Масштаб: Пружина на вход, плавное уменьшение на выход
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeInBack, // Красивое "втягивание" обратно
    );

    // Прозрачность
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );

    // Сдвиг
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3), 
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart, // Исправлено (вместо outQuart)
      reverseCurve: Curves.easeIn,
    ));

    // 1. Запускаем анимацию появления
    _controller.forward();

    // 2. Заводим таймер на исчезновение
    _dismissTimer = Timer(widget.displayDuration, () {
      _triggerExit();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // Метод, который запускает обратную анимацию, и только потом закрывает SnackBar
  Future<void> _triggerExit() async {
    // Если уже в процессе закрытия или виджет удален — выходим
    if (!mounted) return;
    
    _dismissTimer?.cancel();

    try {
      // Ждем завершения обратной анимации
      await _controller.reverse().orCancel;
    } catch (e) {
      // Игнорируем ошибки анимации (если виджет демонтирован в процессе)
    }

    if (mounted) {
      // Теперь говорим мессенджеру, что можно удалять SnackBar
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: GlassSurface(
            borderRadius: 20,
            blurSigma: 16,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            borderColor: widget.accent.withOpacity(0.35),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: widget.accent.withOpacity(0.95),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.accent.withOpacity(0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
                if (widget.actionLabel != null && widget.onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: TextButton(
                      // При нажатии кнопки действия тоже сначала анимируем выход
                      onPressed: () async {
                         await _triggerExit();
                         widget.onAction!();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: widget.accent.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        widget.actionLabel!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: widget.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  // При нажатии крестика тоже анимируем выход
                  onPressed: _triggerExit, 
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: cs.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}