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
      return GlassSurface(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
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
                    ChatAttachOption(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedAlbum01,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      label: 'Фото',
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        HapticFeedback.selectionClick();
                        if (onPickPhotos != null) await onPickPhotos();
                      },
                    ),

                    ChatAttachOption(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedFileEmpty02,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      label: 'Файл',
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        HapticFeedback.selectionClick();
                        if (onPickFiles != null) await onPickFiles();
                      },
                    ),

                    // Example: add a third quick action (camera)
                    ChatAttachOption(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedCamera01,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      label: 'Камера',
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        HapticFeedback.selectionClick();
                        if (onTakePhoto != null) await onTakePhoto();
                      },
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

                const SizedBox(height: 8),

                // Cancel button
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Отмена'),
                  ),
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

  const ChatAttachOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
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
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            width: 96,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                  child: HugeIcon(icon: icon.icon, color: icon.color, size: 28),
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
