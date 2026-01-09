import 'package:flutter/material.dart';

import 'package:ren/shared/widgets/glass_surface.dart';

enum GlassSnackKind { info, success, error }

void showGlassSnack(
  BuildContext context,
  String message, {
  GlassSnackKind kind = GlassSnackKind.info,
  Duration duration = const Duration(seconds: 2),
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
      duration: duration,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      content: GlassSurface(
        borderRadius: 18,
        blurSigma: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderColor: accent.withOpacity(0.35),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.95),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => messenger.hideCurrentSnackBar(),
              icon: Icon(
                Icons.close,
                size: 18,
                color: cs.onSurface.withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
