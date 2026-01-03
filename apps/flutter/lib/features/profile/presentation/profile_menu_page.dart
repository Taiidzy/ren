import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:ren/features/profile/presentation/background_personalization_sheet.dart';
import 'package:ren/shared/widgets/background.dart';
import 'package:ren/theme/themes.dart';

class ProfileMenuPage extends StatelessWidget {
  const ProfileMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;
    final matteGlass = AppColors.matteGlassFor(theme.brightness);

    return AppBackground(
      imageOpacity: 1,
      imageBlurSigma: 0,
      imageFit: BoxFit.cover,
      animate: true,
      animationDuration: const Duration(seconds: 20),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    decoration: BoxDecoration(
                      color: matteGlass,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: baseInk.withOpacity(isDark ? 0.20 : 0.12),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(52),
                          child: Image.network(
                            'https://i.pinimg.com/736x/a7/39/43/a73943b7aed2241452dc7d0bd4aa064e.jpg',
                            width: 104,
                            height: 104,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _MenuItem(
                          icon: HugeIcons.strokeRoundedUser,
                          title: 'Профиль',
                          onTap: () {},
                        ),
                        const SizedBox(height: 10),
                        _MenuItem(
                          icon: HugeIcons.strokeRoundedLockPassword,
                          title: 'Приватность',
                          onTap: () {},
                        ),
                        const SizedBox(height: 10),
                        _MenuItem(
                          icon: HugeIcons.strokeRoundedNotification01,
                          title: 'Уведомления',
                          onTap: () {},
                        ),
                        const SizedBox(height: 10),
                        _MenuItem(
                          icon: HugeIcons.strokeRoundedPaintBrush02,
                          title: 'Персонализация',
                          onTap: () {
                            BackgroundPersonalizationSheet.show(context);
                          },
                        ),
                        const SizedBox(height: 10),
                        _MenuItem(
                          icon: HugeIcons.strokeRoundedDatabase,
                          title: 'Хранилище',
                          onTap: () {},
                        ),
                        const SizedBox(height: 12),
                        _MenuItem(
                          icon: HugeIcons.strokeRoundedLogout01,
                          title: 'Выйти',
                          isDanger: true,
                          onTap: () {},
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
  }
}

class _MenuItem extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String title;
  final VoidCallback onTap;
  final bool isDanger;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;
    final matteGlass = AppColors.matteGlassFor(theme.brightness);

    final bg = isDanger
        ? const Color(0xFF991B1B).withOpacity(0.55)
        : matteGlass;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: bg,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: baseInk.withOpacity(isDark ? 0.18 : 0.10),
                ),
              ),
              child: Row(
                children: [
                  HugeIcon(
                    icon: icon,
                    color: theme.colorScheme.onSurface.withOpacity(0.9),
                    size: 20.0,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
