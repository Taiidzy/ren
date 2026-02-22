import 'package:flutter/material.dart';

import 'package:ren/shared/widgets/glass_surface.dart';

class RenContextMenuAction<T> {
  final Widget icon;
  final String label;
  final bool danger;
  final T value;

  const RenContextMenuAction({
    required this.icon,
    required this.label,
    required this.value,
    this.danger = false,
  });
}

class RenContextMenuEntry<T> {
  final RenContextMenuAction<T>? action;
  final bool isDivider;

  const RenContextMenuEntry._({required this.action, required this.isDivider});

  const RenContextMenuEntry.action(RenContextMenuAction<T> action)
    : this._(action: action, isDivider: false);

  const RenContextMenuEntry.divider() : this._(action: null, isDivider: true);
}

class RenContextMenu {
  static Future<T?> show<T>(
    BuildContext context, {
    required Offset globalPosition,
    required List<RenContextMenuEntry<T>> entries,
    double width = 220,
    double itemHeight = 44,
    double dividerHeight = 10,
    double horizontalPadding = 12,
    double verticalPadding = 12,
    double innerVerticalPadding = 8,
    double blurSigma = 18,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final size = overlay.size;

    final media = MediaQuery.of(context);
    final safe = media.padding;
    final rawAvailableWidth =
        size.width - safe.left - safe.right - horizontalPadding * 2;
    final availableWidth = rawAvailableWidth < 120 ? 120.0 : rawAvailableWidth;
    final minMenuWidth = availableWidth < 160 ? availableWidth : 160.0;
    final effectiveWidth = width.clamp(minMenuWidth, availableWidth).toDouble();

    double contentHeight = 0;
    for (final e in entries) {
      if (e.isDivider) {
        contentHeight += dividerHeight;
      } else {
        contentHeight += itemHeight;
      }
    }
    final menuHeight = contentHeight + innerVerticalPadding * 2;

    final minLeft = horizontalPadding + safe.left;
    final maxLeft =
        size.width - effectiveWidth - horizontalPadding - safe.right;

    final minTop = verticalPadding + safe.top;
    final maxTop = size.height - menuHeight - verticalPadding - safe.bottom;

    final left = (globalPosition.dx).clamp(
      minLeft,
      maxLeft < minLeft ? minLeft : maxLeft,
    );
    final top = (globalPosition.dy).clamp(
      minTop,
      maxTop < minTop ? minTop : maxTop,
    );

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'context_menu',
      barrierColor: Colors.black.withOpacity(0.08),
      pageBuilder: (ctx, a1, a2) {
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: GlassSurface(
                  width: effectiveWidth,
                  blurSigma: blurSigma,
                  borderRadius: 16,
                  padding: EdgeInsets.symmetric(vertical: innerVerticalPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in entries) ...[
                        if (e.isDivider)
                          SizedBox(height: dividerHeight)
                        else
                          _RenContextMenuItem<T>(
                            action: e.action!,
                            height: itemHeight,
                            onTap: () => Navigator.of(ctx).pop(e.action!.value),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RenContextMenuItem<T> extends StatelessWidget {
  final RenContextMenuAction<T> action;
  final double height;
  final VoidCallback onTap;

  const _RenContextMenuItem({
    required this.action,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = action.danger
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface.withOpacity(0.9);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(color: c, size: 18),
                  child: action.icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
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
