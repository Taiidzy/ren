import 'package:flutter/material.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class GlassConfirmDialog extends StatelessWidget {
  final String title;
  final String text;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;
  final Widget? titleLeading;
  final Color? confirmColor;

  const GlassConfirmDialog({
    super.key,
    required this.title,
    required this.text,
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel = 'Отмена',
    this.onCancel,
    this.titleLeading,
    this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;
    final width = MediaQuery.sizeOf(context).width;
    final horizontalInset = width < 360 ? 12.0 : 18.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: 24,
      ),
      child: GlassSurface(
        borderRadius: 22,
        blurSigma: 14,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        borderColor: baseInk.withOpacity(isDark ? 0.22 : 0.12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (titleLeading == null)
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              Row(
                children: [
                  titleLeading!,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.75),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: GlassSurface(
                      borderRadius: 14,
                      blurSigma: 12,
                      borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.10),
                      onTap: onCancel ?? () => Navigator.of(context).pop(false),
                      child: Center(
                        child: Text(
                          cancelLabel,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: GlassSurface(
                      borderRadius: 14,
                      blurSigma: 12,
                      color:
                          confirmColor ??
                          const Color(0xFF991B1B).withOpacity(0.55),
                      borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.10),
                      onTap: onConfirm,
                      child: Center(
                        child: Text(
                          confirmLabel,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
