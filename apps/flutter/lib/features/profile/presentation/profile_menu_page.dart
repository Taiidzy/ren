import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/features/auth/presentation/auth_page.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/profile/presentation/widgets/personalization_sheet.dart';
import 'package:ren/features/profile/presentation/widgets/profile_edit_sheet.dart';
import 'package:ren/features/profile/presentation/widgets/storage_sheet.dart';
import 'package:ren/features/profile/presentation/widgets/notifications_sheet.dart';
import 'package:ren/features/profile/data/profile_repository.dart';
import 'package:ren/features/profile/presentation/profile_store.dart';
import 'package:ren/features/profile/presentation/widgets/security_sheet.dart';
import 'package:ren/shared/widgets/adaptive_page_route.dart';
import 'package:ren/shared/widgets/background.dart';
import 'package:ren/shared/widgets/glass_confirm_dialog.dart';
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

    final shouldLogout = await GlassOverlays.showGlassDialog<bool>(
      context,
      builder: (dialogContext) {
        return GlassConfirmDialog(
          title: 'Выйти из аккаунта?',
          text:
              'Мы очистим защищённое хранилище и вернём тебя на экран авторизации.',
          confirmLabel: 'Выйти',
          onConfirm: () => Navigator.of(dialogContext).pop(true),
          titleLeading: HugeIcon(
            icon: HugeIcons.strokeRoundedLogout01,
            color: theme.colorScheme.onSurface.withOpacity(0.9),
            size: 22,
          ),
        );
      },
    );

    if (shouldLogout != true) return;

    try {
      await context.read<ProfileRepository>().logout();
    } catch (_) {}

    try {
      await context.read<RealtimeClient>().disconnect();
    } catch (_) {}
    context.read<ChatsRepository>().resetSessionState();
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
                          SecuritySheet.show(context);
                        },
                      ),
                      const SizedBox(height: 10),
                      _MenuItem(
                        icon: HugeIcons.strokeRoundedNotification01,
                        title: 'Уведомления',
                        onTap: () {
                          NotificationsSheet.show(context);
                        },
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
                        onTap: () {
                          StorageSheet.show(context);
                        },
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
