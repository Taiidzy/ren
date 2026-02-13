import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/features/auth/presentation/auth_page.dart';
import 'package:ren/features/profile/presentation/widgets/personalization_sheet.dart';
import 'package:ren/features/profile/presentation/widgets/profile_edit_sheet.dart';
import 'package:ren/features/profile/data/profile_repository.dart';
import 'package:ren/features/profile/presentation/profile_store.dart';
import 'package:ren/features/profile/presentation/security_page.dart';
import 'package:ren/shared/widgets/adaptive_page_route.dart';
import 'package:ren/shared/widgets/background.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ProfileMenuPage extends StatelessWidget {
  const ProfileMenuPage({super.key});

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p.characters.first).take(2).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

  Future<void> _confirmAndLogout(BuildContext context) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    final shouldLogout = await GlassOverlays.showGlassDialog<bool>(
      context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
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
                Row(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedLogout01,
                      color: theme.colorScheme.onSurface.withOpacity(0.9),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Выйти из аккаунта?',
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
                  'Мы очистим защищённое хранилище и вернём тебя на экран авторизации.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.75),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: GlassSurface(
                        borderRadius: 14,
                        blurSigma: 12,
                        height: 44,
                        borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.10),
                        onTap: () => Navigator.of(dialogContext).pop(false),
                        child: Center(
                          child: Text(
                            'Отмена',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GlassSurface(
                        borderRadius: 14,
                        blurSigma: 12,
                        height: 44,
                        color: const Color(0xFF991B1B).withOpacity(0.55),
                        borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.10),
                        onTap: () => Navigator.of(dialogContext).pop(true),
                        child: Center(
                          child: Text(
                            'Выйти',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
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
      },
    );

    if (shouldLogout != true) return;

    try {
      await context.read<ProfileRepository>().logout();
    } catch (_) {}

    await SecureStorage.deleteAllKeys();
    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      adaptivePageRoute((_) => const AuthPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    final store = context.watch<ProfileStore>();
    if (store.user == null && !store.isLoading && store.error == null) {
      Future.microtask(() => context.read<ProfileStore>().loadMe());
    }

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
          flexibleSpace: const GlassAppBarBackground(),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: GlassSurface(
                borderRadius: 24,
                blurSigma: 14,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 104,
                        height: 104,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(52),
                          child: (store.user?.avatar ?? '').isEmpty
                              ? Container(
                                  color: theme.colorScheme.surface,
                                  child: Center(
                                    child: Text(
                                      _initials(store.user?.username ?? ''),
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 28,
                                      ),
                                    ),
                                  ),
                                )
                              : Image.network(
                                  store.user!.avatar!,
                                  width: 104,
                                  height: 104,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stack) {
                                    return Container(
                                      color: theme.colorScheme.surface,
                                      child: Center(
                                        child: Text(
                                          _initials(store.user?.username ?? ''),
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 28,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _MenuItem(
                        icon: HugeIcons.strokeRoundedUser,
                        title: 'Профиль',
                        onTap: () {
                          ProfileEditSheet.show(context);
                        },
                      ),
                      const SizedBox(height: 10),
                      _MenuItem(
                        materialIcon: Icons.shield_outlined,
                        title: 'Безопасность',
                        onTap: () {
                          SecurityPage.show(context);
                        },
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
                          PersonalizationSheet.show(context);
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
                        onTap: () {
                          _confirmAndLogout(context);
                        },
                      ),
                    ],
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
  final List<List<dynamic>>? icon;
  final IconData? materialIcon;
  final String title;
  final VoidCallback onTap;
  final bool isDanger;

  const _MenuItem({
    this.icon,
    this.materialIcon,
    required this.title,
    required this.onTap,
    this.isDanger = false,
  }) : assert(icon != null || materialIcon != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    final bg = isDanger ? const Color(0xFF991B1B).withOpacity(0.55) : null;

    return GlassSurface(
      borderRadius: 16,
      blurSigma: 12,
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: bg,
      borderColor: baseInk.withOpacity(isDark ? 0.18 : 0.10),
      onTap: onTap,
      child: Row(
        children: [
          if (icon != null)
            HugeIcon(
              icon: icon!,
              color: theme.colorScheme.onSurface.withOpacity(0.9),
              size: 20.0,
            )
          else
            Icon(
              materialIcon,
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
    );
  }
}
