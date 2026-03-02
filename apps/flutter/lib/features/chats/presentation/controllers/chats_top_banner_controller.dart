import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ren/shared/widgets/avatar.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ChatsTopBannerController {
  OverlayEntry? _entry;
  Timer? _timer;
  _TopBannerOverlayState? _activeState;

  void show({
    required BuildContext context,
    required String title,
    required String body,
    required String avatarUrl,
    required String avatarName,
    required VoidCallback onTap,
    Duration duration = const Duration(seconds: 3),
  }) {
    _timer?.cancel();
    _timer = null;
    _removeCurrent(immediate: true);

    final overlay = Overlay.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) {
        return _TopBannerOverlay(
          onStateReady: (state) => _activeState = state,
          onDismissed: () => _remove(entry),
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    onTap: () {
                      _activeState?.dismiss();
                      onTap();
                    },
                    child: GlassSurface(
                      borderRadius: 18,
                      blurSigma: 14,
                      borderColor: baseInk.withOpacity(isDark ? 0.18 : 0.10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Row(
                          children: [
                            RenAvatar(
                              url: avatarUrl,
                              name: avatarName,
                              isOnline: false,
                              size: 34,
                              onlineDotSize: 0,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.85),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.65,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _entry = entry;
    overlay.insert(entry);

    _timer = Timer(duration, () {
      _activeState?.dismiss();
    });
  }

  void _removeCurrent({required bool immediate}) {
    _timer?.cancel();
    _timer = null;
    if (immediate) {
      _entry?.remove();
      _entry = null;
      _activeState = null;
      return;
    }
    _activeState?.dismiss();
  }

  void _remove(OverlayEntry entry) {
    entry.remove();
    if (_entry == entry) {
      _entry = null;
    }
    _activeState = null;
  }

  void dispose() {
    _removeCurrent(immediate: true);
  }
}

class _TopBannerOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismissed;
  final void Function(_TopBannerOverlayState state) onStateReady;

  const _TopBannerOverlay({
    required this.child,
    required this.onDismissed,
    required this.onStateReady,
  });

  @override
  State<_TopBannerOverlay> createState() => _TopBannerOverlayState();
}

class _TopBannerOverlayState extends State<_TopBannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  );
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    widget.onStateReady(this);
    _controller.forward();
  }

  Future<void> dismiss() async {
    if (_isDismissing) return;
    _isDismissing = true;
    await _controller.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, -0.28),
      end: Offset.zero,
    ).animate(curved);
    final fade = Tween<double>(begin: 0, end: 1).animate(curved);
    final scale = Tween<double>(begin: 0.965, end: 1).animate(curved);

    return IgnorePointer(
      ignoring: _isDismissing,
      child: FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: ScaleTransition(scale: scale, child: widget.child),
        ),
      ),
    );
  }
}
