import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ren/core/providers/notifications_settings.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class NotificationsSheet {
  static Future<void> show(BuildContext context) async {
    await GlassOverlays.showGlassBottomSheet<void>(
      context,
      builder: (_) => const _NotificationsSheetBody(),
    );
  }
}

class _NotificationsSheetBody extends StatelessWidget {
  const _NotificationsSheetBody();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<NotificationsSettings>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return DraggableScrollableSheet(
      initialChildSize: 0.58,
      minChildSize: 0.36,
      maxChildSize: 0.86,
      builder: (context, scrollController) {
        return GlassSurface(
          blurSigma: 16,
          borderRadiusGeometry: const BorderRadius.only(
            topLeft: Radius.circular(26),
            topRight: Radius.circular(26),
          ),
          borderColor: baseInk.withOpacity(isDark ? 0.22 : 0.12),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Уведомления',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Настройте отклик и поведение уведомлений в приложении.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.75),
                ),
              ),
              const SizedBox(height: 14),
              GlassSurface(
                borderRadius: 16,
                blurSigma: 12,
                borderColor: baseInk.withOpacity(isDark ? 0.18 : 0.10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: SwitchListTile.adaptive(
                  value: settings.hapticEnabled,
                  onChanged: (v) => settings.setHapticEnabled(v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Haptic при новых сообщениях'),
                  subtitle: Text(
                    'Лёгкий тактильный отклик, когда приходят новые сообщения, пока вы не внизу чата.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.72),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GlassSurface(
                borderRadius: 16,
                blurSigma: 12,
                borderColor: baseInk.withOpacity(isDark ? 0.18 : 0.10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: SwitchListTile.adaptive(
                  value: settings.inAppBannersEnabled,
                  onChanged: (v) => settings.setInAppBannersEnabled(v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In-app баннеры'),
                  subtitle: Text(
                    'Показывать верхний баннер новых сообщений, когда приложение открыто.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.72),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GlassSurface(
                borderRadius: 16,
                blurSigma: 12,
                borderColor: baseInk.withOpacity(isDark ? 0.18 : 0.10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: SwitchListTile.adaptive(
                  value: settings.inAppSoundEnabled,
                  onChanged: (v) => settings.setInAppSoundEnabled(v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In-app звук'),
                  subtitle: Text(
                    'Короткий системный звук при новых сообщениях в открытом приложении.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.72),
                    ),
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
