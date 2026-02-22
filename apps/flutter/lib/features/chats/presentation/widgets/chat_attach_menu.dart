import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

Future<void> showChatAttachMenu(
  BuildContext context, {
  required Future<void> Function()? onPickPhotos,
  required Future<void> Function()? onPickFiles,
  required Future<void> Function()? onTakePhoto,
}) async {
  final theme = Theme.of(context);

  await GlassOverlays.showGlassBottomSheet<void>(
    context,
    builder: (ctx) {
      final compact = MediaQuery.sizeOf(ctx).width < 360;
      final horizontalPadding = compact ? 12.0 : 16.0;
      final optionSpacing = compact ? 8.0 : 12.0;
      return GlassSurface(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: 16,
              horizontal: horizontalPadding,
            ),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  height: 4,
                  width: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 12),

                // Title / optional subtitle
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Добавить',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Options row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ChatAttachOption(
                        compact: compact,
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedAlbum01,
                          color: theme.colorScheme.primary,
                          size: compact ? 24 : 28,
                        ),
                        label: 'Фото',
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          HapticFeedback.selectionClick();
                          if (onPickPhotos != null) await onPickPhotos();
                        },
                      ),
                    ),
                    SizedBox(width: optionSpacing),

                    Expanded(
                      child: ChatAttachOption(
                        compact: compact,
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedFileEmpty02,
                          color: theme.colorScheme.primary,
                          size: compact ? 24 : 28,
                        ),
                        label: 'Файл',
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          HapticFeedback.selectionClick();
                          if (onPickFiles != null) await onPickFiles();
                        },
                      ),
                    ),
                    SizedBox(width: optionSpacing),

                    // Example: add a third quick action (camera)
                    Expanded(
                      child: ChatAttachOption(
                        compact: compact,
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedCamera01,
                          color: theme.colorScheme.primary,
                          size: compact ? 24 : 28,
                        ),
                        label: 'Камера',
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          HapticFeedback.selectionClick();
                          if (onTakePhoto != null) await onTakePhoto();
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Optional explanatory text
                Text(
                  'Выберите источник, чтобы прикрепить файл или фото',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ChatAttachOption extends StatelessWidget {
  final HugeIcon icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  const ChatAttachOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: compact ? 6 : 8,
              horizontal: compact ? 4 : 6,
            ),
            constraints: BoxConstraints(minHeight: compact ? 88 : 96),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: compact ? 24 : 28,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                  child: HugeIcon(
                    icon: icon.icon,
                    color: icon.color,
                    size: compact ? 24 : 28,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
