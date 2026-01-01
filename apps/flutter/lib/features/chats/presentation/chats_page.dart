import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:hugeicons/hugeicons.dart';

import 'package:ren/features/chats/data/fake_chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/features/chats/presentation/chat_page.dart';
import 'package:ren/features/profile/presentation/profile_menu_page.dart';

import 'package:ren/theme/themes.dart';

import 'package:ren/shared/widgets/background.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({Key? key}) : super(key: key);
  @override
  State<ChatsPage> createState() => _HomePageState();
}

class _HomePageState extends State<ChatsPage> {
  final _repo = const FakeChatsRepository();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final baseInk = isDark ? Colors.white : Colors.black;
    final favorites = _repo.favorites();
    final chats = _repo.chats();
    return AppBackground(
      // Опционально: передайте картинку, чтобы она была задним фоном
      // backgroundImage: AssetImage('assets/wallpapers/my_bg.jpg'),
      // backgroundImage: NetworkImage('https://...'),
      // backgroundImage: FileImage(File(pathFromPicker)),
      imageOpacity: 1, // прозрачность картинки
      imageBlurSigma: 0, // блюр картинки (0 — без блюра)
      imageFit: BoxFit.cover, // как вписывать изображение
      showGradient: true, // показывать ли градиент поверх
      gradientOpacity: 1, // прозрачность градиента
      animate: true, // включить анимацию
      animationDuration: Duration(seconds: 20),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Чаты',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          centerTitle: true,
          backgroundColor: AppColors.matteGlass,
          elevation: 0,
          actions: [
            IconButton(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedSettings01,
                color: theme.colorScheme.onSurface,
                size: 24.0,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const ProfileMenuPage(),
                    transitionsBuilder: (_, anim, __, child) =>
                        FadeTransition(opacity: anim, child: child),
                    transitionDuration: const Duration(milliseconds: 220),
                  ),
                );
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(36),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(64, 0, 64, 4),
              child: TextField(
                cursorColor: theme.colorScheme.primary,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  hintStyle: TextStyle(color: AppColors.matteGlass),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedSearch01,
                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                      size: 14,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 0,
                    minHeight: 0,
                  ),
                  filled: true,
                  fillColor: AppColors.matteGlass,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      decoration: BoxDecoration(
                        color: AppColors.matteGlass,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: baseInk.withOpacity(isDark ? 0.20 : 0.12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Text(
                              'Избранные',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 72,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        for (int i = 0;
                                            i < favorites.length;
                                            i++) ...[
                                          if (i != 0)
                                            const SizedBox(width: 12),
                                          _FavoriteItem(
                                            user: favorites[i],
                                            onTap: () {
                                              final user = favorites[i];
                                              final chat = ChatPreview(
                                                id: 'fav_${user.id}',
                                                user: user,
                                                lastMessage: 'Какая?',
                                                lastMessageAt: DateTime.now(),
                                              );

                                              Navigator.of(context).push(
                                                PageRouteBuilder(
                                                  pageBuilder: (_, __, ___) =>
                                                      ChatPage(chat: chat),
                                                  transitionsBuilder:
                                                      (_, anim, __, child) =>
                                                          FadeTransition(
                                                    opacity: anim,
                                                    child: child,
                                                  ),
                                                  transitionDuration:
                                                      const Duration(
                                                    milliseconds: 220,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: chats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      return _ChatTile(
                        chat: chat,
                        onTap: () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (_, __, ___) => ChatPage(chat: chat),
                              transitionsBuilder: (_, anim, __, child) =>
                                  FadeTransition(opacity: anim, child: child),
                              transitionDuration:
                                  const Duration(milliseconds: 220),
                            ),
                          );
                        },
                      );
                    },
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

class _FavoriteItem extends StatelessWidget {
  final ChatUser user;
  final VoidCallback onTap;

  const _FavoriteItem({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const double avatarSize = 52;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FavoriteAvatar(
                url: user.avatarUrl,
                isOnline: user.isOnline,
                size: avatarSize,
              ),
              const SizedBox(height: 2),
              Text(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withOpacity(0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteAvatar extends StatelessWidget {
  final String url;
  final bool isOnline;
  final double size;

  const _FavoriteAvatar({
    required this.url,
    required this.isOnline,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: Image.network(url, width: size, height: size, fit: BoxFit.cover),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: isOnline
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF9CA3AF),
                shape: BoxShape.circle,
                border:
                    Border.all(color: Colors.black.withOpacity(0.25), width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final ChatPreview chat;
  final VoidCallback onTap;

  const _ChatTile({required this.chat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: AppColors.matteGlass,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: baseInk.withOpacity(isDark ? 0.20 : 0.12),
                ),
              ),
              child: Row(
                children: [
                  _Avatar(url: chat.user.avatarUrl, isOnline: chat.user.isOnline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chat.user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          chat.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.70),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _formatTime(chat.lastMessageAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.60),
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

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _Avatar extends StatelessWidget {
  final String url;
  final bool isOnline;

  const _Avatar({required this.url, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.network(url, width: 44, height: 44, fit: BoxFit.cover),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isOnline
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF9CA3AF),
                shape: BoxShape.circle,
                border:
                    Border.all(color: Colors.black.withOpacity(0.25), width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
