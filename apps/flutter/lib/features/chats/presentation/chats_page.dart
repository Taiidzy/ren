import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/features/chats/presentation/chat_page.dart';
import 'package:ren/features/profile/presentation/profile_menu_page.dart';

import 'package:ren/core/realtime/realtime_client.dart';

import 'package:ren/shared/widgets/background.dart';
import 'package:ren/shared/widgets/adaptive_page_route.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({Key? key}) : super(key: key);
  @override
  State<ChatsPage> createState() => _HomePageState();
}

class _HomePageState extends State<ChatsPage> {
  late final Future<List<ChatPreview>> _chatsFuture;
  final Map<String, bool> _online = {};
  RealtimeClient? _rt;
  StreamSubscription? _rtSub;

  @override
  void initState() {
    super.initState();
    _chatsFuture = context.read<ChatsRepository>().fetchChats();
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _rtSub = null;
    super.dispose();
  }

  Future<void> _ensureRealtime(List<ChatPreview> chats) async {
    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;

    if (!rt.isConnected) {
      await rt.connect();
    }

    final contacts = <int>[];
    for (final c in chats) {
      final pid = c.peerId;
      if (pid != null && pid > 0) contacts.add(pid);
    }
    rt.init(contacts: contacts);

    _rtSub ??= rt.events.listen((evt) {
      if (evt.type == 'presence') {
        final userId = evt.data['user_id'];
        final status = (evt.data['status'] as String?) ?? '';
        final idStr = '$userId';
        final isOnline = status == 'online';
        if (_online[idStr] != isOnline) {
          setState(() {
            _online[idStr] = isOnline;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final baseInk = isDark ? Colors.white : Colors.black;
    return AppBackground(
      // Опционально: передайте картинку, чтобы она была задним фоном
      // backgroundImage: AssetImage('assets/wallpapers/my_bg.jpg'),
      // backgroundImage: NetworkImage('https://...'),
      // backgroundImage: FileImage(File(pathFromPicker)),
      imageOpacity: 1, // прозрачность картинки
      imageBlurSigma: 0, // блюр картинки (0 — без блюра)
      imageFit: BoxFit.cover, // как вписывать изображение
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: const GlassAppBarBackground(),
          actions: [
            IconButton(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedSettings01,
                color: theme.colorScheme.onSurface,
                size: 24.0,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  adaptivePageRoute((_) => const ProfileMenuPage()),
                );
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(36),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(64, 0, 64, 4),
              child: GlassSurface(
                borderRadius: 8,
                blurSigma: 12,
                borderColor: baseInk.withOpacity(isDark ? 0.18 : 0.10),
                child: TextField(
                  cursorColor: theme.colorScheme.primary,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Поиск',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                    ),
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
                    filled: false,
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
        ),
        body: SafeArea(
          bottom: false,
          child: FutureBuilder<List<ChatPreview>>(
            future: _chatsFuture,
            builder: (context, snapshot) {
              final chats = snapshot.data ?? const <ChatPreview>[];

              final isLoading = snapshot.connectionState == ConnectionState.waiting;

              if (snapshot.hasData) {
                Future.microtask(() => _ensureRealtime(chats));
              }

              final decoratedChats = chats
                  .map(
                    (c) => ChatPreview(
                      id: c.id,
                      peerId: c.peerId,
                      kind: c.kind,
                      user: ChatUser(
                        id: c.user.id,
                        name: c.user.name,
                        avatarUrl: c.user.avatarUrl,
                        isOnline: _online[c.user.id] ?? c.user.isOnline,
                      ),
                      lastMessage: c.lastMessage,
                      lastMessageAt: c.lastMessageAt,
                    ),
                  )
                  .toList();

              final favorites = decoratedChats.take(8).map((c) => c.user).toList();

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  children: [
                    GlassSurface(
                      borderRadius: 22,
                      blurSigma: 14,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.12),
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
                            height: 74,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (isLoading) ...[
                                          for (int i = 0; i < 8; i++) ...[
                                            if (i != 0) const SizedBox(width: 12),
                                            const _SkeletonFavoriteItem(),
                                          ]
                                        ] else ...[
                                          for (int i = 0; i < favorites.length; i++) ...[
                                            if (i != 0) const SizedBox(width: 12),
                                            _FavoriteItem(
                                              user: favorites[i],
                                              onTap: () {
                                                final user = favorites[i];
                                                final chat = chats.firstWhere(
                                                  (c) => c.user.id == user.id,
                                                );
                                                Navigator.of(context).push(
                                                  adaptivePageRoute(
                                                    (_) => ChatPage(chat: chat),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
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
                    const SizedBox(height: 14),
                    Expanded(
                      child: isLoading
                          ? ListView.separated(
                              padding: const EdgeInsets.only(bottom: 16),
                              itemCount: 10,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                return const _SkeletonChatTile();
                              },
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 16),
                              itemCount: decoratedChats.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final chat = decoratedChats[index];
                                return _ChatTile(
                                  chat: chat,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      adaptivePageRoute((_) => ChatPage(chat: chat)),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SkeletonFavoriteItem extends StatelessWidget {
  const _SkeletonFavoriteItem();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SkeletonBox(width: 52, height: 52, radius: 16),
          SizedBox(height: 6),
          _SkeletonBox(width: 46, height: 10, radius: 6),
        ],
      ),
    );
  }
}

class _SkeletonChatTile extends StatelessWidget {
  const _SkeletonChatTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return GlassSurface(
      borderRadius: 18,
      blurSigma: 14,
      borderColor: baseInk.withOpacity(isDark ? 0.18 : 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const _SkeletonBox(width: 46, height: 46, radius: 16),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _SkeletonBox(width: 140, height: 14, radius: 8),
                SizedBox(height: 8),
                _SkeletonBox(width: 200, height: 12, radius: 8),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const _SkeletonBox(width: 32, height: 12, radius: 8),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black;

    final c1 = base.withOpacity(isDark ? 0.10 : 0.06);
    final c2 = base.withOpacity(isDark ? 0.18 : 0.10);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final begin = Alignment(-1.0 - 2.0 * t, 0);
        final end = Alignment(1.0 - 2.0 * t, 0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: begin,
                end: end,
                colors: [c1, c2, c1],
                stops: const [0.2, 0.5, 0.8],
              ),
            ),
          ),
        );
      },
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
                name: user.name,
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
  final String name;
  final bool isOnline;
  final double size;

  const _FavoriteAvatar({
    required this.url,
    required this.name,
    required this.isOnline,
    required this.size,
  });

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p.characters.first).take(2).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

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
            child: url.isEmpty
                ? Container(
                    color: Theme.of(context).colorScheme.surface,
                    child: Center(
                      child: Text(
                        _initials(name),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: size * 0.34,
                        ),
                      ),
                    ),
                  )
                : Image.network(
                    url,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) {
                      return Container(
                        color: Theme.of(context).colorScheme.surface,
                        child: Center(
                          child: Text(
                            _initials(name),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: size * 0.34,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
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

    return GlassSurface(
      borderRadius: 18,
      blurSigma: 14,
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.12),
      onTap: onTap,
      child: Row(
        children: [
          _Avatar(
            url: chat.user.avatarUrl,
            name: chat.user.name,
            isOnline: chat.user.isOnline,
          ),
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
                    color: theme.colorScheme.onSurface.withOpacity(0.70),
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
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final bool isOnline;

  const _Avatar({required this.url, required this.name, required this.isOnline});

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p.characters.first).take(2).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: url.isEmpty
                ? Container(
                    width: 48,
                    height: 48,
                    color: Theme.of(context).colorScheme.surface,
                    child: Center(
                      child: Text(
                        _initials(name),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                : Image.network(
                    url,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) {
                      return Container(
                        width: 48,
                        height: 48,
                        color: Theme.of(context).colorScheme.surface,
                        child: Center(
                          child: Text(
                            _initials(name),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
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
