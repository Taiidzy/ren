import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/features/chats/presentation/chat_page.dart';
import 'package:ren/features/profile/presentation/profile_menu_page.dart';

import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/core/notifications/local_notifications.dart';

import 'package:ren/shared/widgets/background.dart';
import 'package:ren/shared/widgets/adaptive_page_route.dart';
import 'package:ren/shared/widgets/avatar.dart';
import 'package:ren/shared/widgets/skeleton.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';
import 'package:ren/shared/widgets/context_menu.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({Key? key}) : super(key: key);
  @override
  State<ChatsPage> createState() => _HomePageState();
}

class _UserSearchTile extends StatelessWidget {
  final ChatUser user;
  final VoidCallback onTap;

  const _UserSearchTile({required this.user, required this.onTap});

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
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
              backgroundImage: (user.avatarUrl.isNotEmpty)
                  ? NetworkImage(user.avatarUrl)
                  : null,
              child: (user.avatarUrl.isEmpty)
                  ? Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${user.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              color: theme.colorScheme.onSurface.withOpacity(0.65),
              size: 18.0,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePageState extends State<ChatsPage> with WidgetsBindingObserver {
  List<ChatPreview> _chats = const [];
  bool _isInitialChatsLoading = true;
  final Map<String, bool> _online = {};
  final Map<int, ChatPreview> _chatIndex = {};
  RealtimeClient? _rt;
  StreamSubscription? _rtSub;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  List<ChatUser> _userResults = const [];
  bool _isSearchingUsers = false;
  String? _userSearchError;
  int _userSearchSeq = 0;

  bool _isForeground = true;

  OverlayEntry? _topBanner;
  Timer? _topBannerTimer;

  Future<void> _reloadChats() async {
    await _syncChats();
  }

  bool _isChatsDifferent(List<ChatPreview> a, List<ChatPreview> b) {
    if (identical(a, b)) return false;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.user.id != y.user.id ||
          x.user.name != y.user.name ||
          x.user.avatarUrl != y.user.avatarUrl ||
          x.lastMessage != y.lastMessage ||
          x.isFavorite != y.isFavorite ||
          x.lastMessageAt.millisecondsSinceEpoch !=
              y.lastMessageAt.millisecondsSinceEpoch) {
        return true;
      }
    }
    return false;
  }

  Future<void> _loadChatsOfflineFirst() async {
    final repo = context.read<ChatsRepository>();
    final cached = await repo.getCachedChats();
    if (!mounted) return;
    setState(() {
      _chats = cached;
      _isInitialChatsLoading = false;
    });
    if (cached.isNotEmpty) {
      unawaited(_ensureRealtime(cached));
    }
    unawaited(_syncChats());
  }

  Future<void> _syncChats() async {
    final repo = context.read<ChatsRepository>();
    try {
      final fresh = await repo.syncChats();
      if (!mounted) return;
      if (_isChatsDifferent(_chats, fresh)) {
        setState(() {
          _chats = fresh;
          _isInitialChatsLoading = false;
        });
      } else if (_isInitialChatsLoading) {
        setState(() {
          _isInitialChatsLoading = false;
        });
      }
      if (fresh.isNotEmpty) {
        unawaited(_ensureRealtime(fresh));
      }
    } catch (e) {
      if (!mounted) return;
      if (_isInitialChatsLoading) {
        setState(() {
          _isInitialChatsLoading = false;
        });
      }
      if (_chats.isEmpty) {
        showGlassSnack(
          context,
          'Не удалось синхронизировать чаты: $e',
          kind: GlassSnackKind.error,
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadChatsOfflineFirst());
    _searchCtrl.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 250), () {
        final next = _searchCtrl.text.trim();
        if (next == _query) return;
        setState(() {
          _query = next;
        });
        _runUserSearch(next);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _topBannerTimer?.cancel();
    _topBannerTimer = null;
    _topBanner?.remove();
    _topBanner = null;
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _searchCtrl.dispose();
    _rtSub?.cancel();
    _rtSub = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
  }

  void _showTopGlassBanner({
    required String title,
    required String body,
    required String avatarUrl,
    required String avatarName,
    required VoidCallback onTap,
    Duration duration = const Duration(seconds: 3),
  }) {
    _topBannerTimer?.cancel();
    _topBannerTimer = null;
    _topBanner?.remove();
    _topBanner = null;

    final overlay = Overlay.of(context);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: () {
                    entry.remove();
                    if (_topBanner == entry) {
                      _topBanner = null;
                    }
                    onTap();
                  },
                  child: GlassSurface(
                    borderRadius: 18,
                    blurSigma: 14,
                    borderColor: baseInk.withOpacity(isDark ? 0.18 : 0.10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Row(
                        children: [
                          RenAvatar(
                            url: avatarUrl,
                            name: avatarName,
                            isOnline: false,
                            size: 34,
                            onlineDotSize: 0,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.85),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.65,
                            ),
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
      },
    );

    _topBanner = entry;
    overlay.insert(entry);

    _topBannerTimer = Timer(duration, () {
      entry.remove();
      if (_topBanner == entry) {
        _topBanner = null;
      }
    });
  }

  void _runUserSearch(String query) {
    final q = query.trim();
    final seq = ++_userSearchSeq;

    if (q.isEmpty) {
      setState(() {
        _isSearchingUsers = false;
        _userSearchError = null;
        _userResults = const [];
      });
      return;
    }

    setState(() {
      _isSearchingUsers = true;
      _userSearchError = null;
    });

    final repo = context.read<ChatsRepository>();
    repo
        .searchUsers(q)
        .then((users) {
          if (!mounted) return;
          if (seq != _userSearchSeq) return;
          setState(() {
            _isSearchingUsers = false;
            _userSearchError = null;
            _userResults = users;
          });
        })
        .catchError((e) {
          if (!mounted) return;
          if (seq != _userSearchSeq) return;
          setState(() {
            _isSearchingUsers = false;
            _userSearchError = e.toString();
            _userResults = const [];
          });
        });
  }

  Future<void> _createChatFlow() async {
    final controller = TextEditingController();
    final peerId = await GlassOverlays.showGlassDialog<int>(
      context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Новый чат'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'ID пользователя'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final id = int.tryParse(controller.text.trim());
                if (id == null || id <= 0) {
                  Navigator.of(context).pop(null);
                  return;
                }
                Navigator.of(context).pop(id);
              },
              child: const Text('Создать'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (peerId == null) {
      if (controller.text.trim().isNotEmpty) {
        showGlassSnack(
          context,
          'Укажите корректный ID пользователя',
          kind: GlassSnackKind.error,
        );
      }
      return;
    }

    try {
      final repo = context.read<ChatsRepository>();
      final chat = await repo.createPrivateChat(peerId);
      if (!mounted) return;
      await _reloadChats();
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(adaptivePageRoute((_) => ChatPage(chat: chat)));
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, e.toString(), kind: GlassSnackKind.error);
    }
  }

  Future<void> _showChatActionsAt(
    ChatPreview chat,
    Offset globalPosition,
  ) async {
    final chatId = int.tryParse(chat.id) ?? 0;
    if (chatId <= 0) return;

    final action = await RenContextMenu.show<String>(
      context,
      globalPosition: globalPosition,
      entries: [
        RenContextMenuEntry.action(
          RenContextMenuAction<String>(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedStar, size: 20),
            label: chat.isFavorite
                ? 'Убрать из избранного'
                : 'Добавить в избранное',
            value: 'favorite',
          ),
        ),
        const RenContextMenuEntry.divider(),
        RenContextMenuEntry.action(
          RenContextMenuAction<String>(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: 20),
            label: 'Удалить чат',
            danger: true,
            value: 'delete',
          ),
        ),
      ],
    );

    if (!mounted) return;
    if (action == null) return;

    if (action == 'favorite') {
      try {
        final repo = context.read<ChatsRepository>();
        await repo.setFavorite(chatId, favorite: !chat.isFavorite);
        await _reloadChats();
      } catch (e) {
        if (!mounted) return;
        showGlassSnack(context, e.toString(), kind: GlassSnackKind.error);
      }
      return;
    }

    if (action == 'delete') {
      final confirm = await GlassOverlays.showGlassDialog<bool>(
        context,
        builder: (dctx) {
          return AlertDialog(
            title: const Text('Удалить чат?'),
            content: const Text('Чат будет удалён из вашего списка.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dctx).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dctx).pop(true),
                child: const Text('Удалить'),
              ),
            ],
          );
        },
      );

      if (confirm != true) return;
      if (!mounted) return;
      try {
        final repo = context.read<ChatsRepository>();
        await repo.deleteChat(chatId);
        await _reloadChats();
      } catch (e) {
        if (!mounted) return;
        showGlassSnack(context, e.toString(), kind: GlassSnackKind.error);
      }
    }
  }

  Future<void> _ensureRealtime(List<ChatPreview> chats) async {
    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;

    _chatIndex
      ..clear()
      ..addEntries(
        chats
            .map((c) => MapEntry(int.tryParse(c.id) ?? 0, c))
            .where((e) => e.key > 0),
      );

    if (!rt.isConnected) {
      await rt.connect();
    }

    final contacts = <int>[];
    for (final c in chats) {
      final pid = c.peerId;
      if (pid != null && pid > 0) contacts.add(pid);
    }
    rt.init(contacts: contacts);

    _rtSub ??= rt.events.listen((evt) async {
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

      if (evt.type == 'notification_new') {
        final repo = context.read<ChatsRepository>();
        final chatIdDyn = evt.data['chat_id'] ?? evt.data['chatId'];
        final chatId = (chatIdDyn is int)
            ? chatIdDyn
            : int.tryParse('$chatIdDyn') ?? 0;
        if (chatId <= 0) return;

        final msg = evt.data['message'];
        if (msg is! Map) return;

        final m = (msg is Map<String, dynamic>)
            ? msg
            : Map<String, dynamic>.fromEntries(
                msg.entries.map((e) => MapEntry(e.key.toString(), e.value)),
              );

        final decoded = await repo.decryptIncomingWsMessageFull(message: m);
        final hasAttachments = decoded.attachments.isNotEmpty;

        final chat = _chatIndex[chatId];
        final title = (chat?.user.name ?? '').trim().isNotEmpty
            ? (chat!.user.name)
            : 'Новое сообщение';

        final body = decoded.text.trim().isNotEmpty
            ? decoded.text.trim()
            : (hasAttachments ? 'Вложение' : 'Сообщение');

        if (!mounted) return;

        if (_isForeground) {
          _showTopGlassBanner(
            title: title,
            body: body,
            avatarUrl: chat?.user.avatarUrl ?? '',
            avatarName: chat?.user.name ?? title,
            onTap: () {
              final c = _chatIndex[chatId];
              if (c == null) return;
              Navigator.of(
                context,
              ).push(adaptivePageRoute((_) => ChatPage(chat: c)));
            },
          );
        } else {
          await LocalNotifications.instance.showMessageNotification(
            chatId: chatId,
            title: title,
            body: body,
            avatarUrl: chat?.user.avatarUrl,
            senderName: chat?.user.name,
          );
        }

        return;
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
          title: ValueListenableBuilder<bool>(
            valueListenable: context.read<ChatsRepository>().chatsSyncing,
            builder: (context, isSyncing, _) {
              return SizedBox(
                width: 124,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'Чаты',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: isSyncing
                            ? SizedBox(
                                key: const ValueKey('syncing'),
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.8),
                                ),
                              )
                            : const SizedBox(
                                key: ValueKey('idle'),
                                width: 14,
                                height: 14,
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
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
                Navigator.of(
                  context,
                ).push(adaptivePageRoute((_) => const ProfileMenuPage()));
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(36),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(64, 0, 64, 4),
              child: GlassSurface(
                blurSigma: 12,
                borderColor: baseInk.withOpacity(0),
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
                    suffixIcon: (_query.isEmpty)
                        ? null
                        : IconButton(
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedCancel01,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.8,
                              ),
                              size: 16.0,
                            ),
                            onPressed: () {
                              _searchCtrl.clear();
                              FocusScope.of(context).unfocus();
                            },
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
                  controller: _searchCtrl,
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Builder(
            builder: (context) {
              final chats = _chats;
              final isLoading = _isInitialChatsLoading && chats.isEmpty;

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
                      isFavorite: c.isFavorite,
                      lastMessage: c.lastMessage,
                      lastMessageAt: c.lastMessageAt,
                    ),
                  )
                  .toList();

              final q = _query.toLowerCase();
              final visibleChats = (q.isEmpty)
                  ? decoratedChats
                  : decoratedChats.where((c) {
                      final name = c.user.name.toLowerCase();
                      final idStr = c.user.id.toLowerCase();
                      return name.contains(q) || idStr.contains(q);
                    }).toList();

              final chatUserIds = decoratedChats.map((c) => c.user.id).toSet();
              final visibleUsers = _userResults
                  .where((u) => !chatUserIds.contains(u.id))
                  .toList(growable: false);

              final favoriteChats = decoratedChats
                  .where((c) => c.isFavorite)
                  .take(5)
                  .toList();
              final favorites = favoriteChats.map((c) => c.user).toList();

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  children: [
                    favoriteChats.isEmpty
                        ? const SizedBox.shrink()
                        : GlassSurface(
                            borderRadius: 22,
                            blurSigma: 14,
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                            borderColor: baseInk.withOpacity(
                              isDark ? 0.20 : 0.12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: Text(
                                    'Избранные',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
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
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (isLoading) ...[
                                                for (int i = 0; i < 5; i++) ...[
                                                  if (i != 0)
                                                    const SizedBox(width: 12),
                                                  const _SkeletonFavoriteItem(),
                                                ],
                                              ] else ...[
                                                for (
                                                  int i = 0;
                                                  i < favorites.length;
                                                  i++
                                                ) ...[
                                                  if (i != 0)
                                                    const SizedBox(width: 12),
                                                  _FavoriteItem(
                                                    user: favorites[i],
                                                    onTap: () {
                                                      final chat =
                                                          favoriteChats[i];
                                                      Navigator.of(
                                                        context,
                                                      ).push(
                                                        adaptivePageRoute(
                                                          (_) => ChatPage(
                                                            chat: chat,
                                                          ),
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
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                return const _SkeletonChatTile();
                              },
                            )
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 16),
                              children: [
                                if (_query.trim().isNotEmpty) ...[
                                  Text(
                                    'Чаты',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                for (final chat in visibleChats) ...[
                                  _ChatTile(
                                    chat: chat,
                                    onLongPressAt: (pos) =>
                                        _showChatActionsAt(chat, pos),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        adaptivePageRoute(
                                          (_) => ChatPage(chat: chat),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                if (_query.trim().isNotEmpty) ...[
                                  Divider(
                                    height: 28,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.18),
                                  ),
                                  Text(
                                    'Пользователи',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (_isSearchingUsers) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ] else if (_userSearchError != null) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Text(
                                        _userSearchError ?? '',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme.colorScheme.error,
                                            ),
                                      ),
                                    ),
                                  ] else if (visibleUsers.isEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Text(
                                        'Ничего не найдено',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withOpacity(0.6),
                                            ),
                                      ),
                                    ),
                                  ] else ...[
                                    for (final user in visibleUsers) ...[
                                      _UserSearchTile(
                                        user: user,
                                        onTap: () async {
                                          final peerId =
                                              int.tryParse(user.id) ?? 0;
                                          if (peerId <= 0) return;

                                          final existing = decoratedChats
                                              .where((c) => c.peerId == peerId)
                                              .cast<ChatPreview?>()
                                              .firstWhere(
                                                (c) => c != null,
                                                orElse: () => null,
                                              );

                                          if (existing != null) {
                                            if (!context.mounted) return;
                                            Navigator.of(context).push(
                                              adaptivePageRoute(
                                                (_) => ChatPage(chat: existing),
                                              ),
                                            );
                                            return;
                                          }

                                          try {
                                            final repo = context
                                                .read<ChatsRepository>();
                                            final chat = await repo
                                                .createPrivateChat(peerId);
                                            if (!context.mounted) return;
                                            await _reloadChats();
                                            if (!context.mounted) return;
                                            Navigator.of(context).push(
                                              adaptivePageRoute(
                                                (_) => ChatPage(chat: chat),
                                              ),
                                            );
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            showGlassSnack(
                                              context,
                                              e.toString(),
                                              kind: GlassSnackKind.error,
                                            );
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  ],
                                ],
                              ],
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
          RenSkeletonBox(width: 52, height: 52, radius: 16),
          SizedBox(height: 6),
          RenSkeletonBox(width: 46, height: 10, radius: 6),
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
          const RenSkeletonBox(width: 46, height: 46, radius: 16),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RenSkeletonBox(width: 140, height: 14, radius: 8),
                SizedBox(height: 8),
                RenSkeletonBox(width: 200, height: 12, radius: 8),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const RenSkeletonBox(width: 32, height: 12, radius: 8),
        ],
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
              RenAvatar(
                url: user.avatarUrl,
                name: user.name,
                isOnline: user.isOnline,
                size: avatarSize,
                onlineDotSize: 11,
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

class _ChatTile extends StatelessWidget {
  final ChatPreview chat;
  final VoidCallback onTap;
  final ValueChanged<Offset> onLongPressAt;

  const _ChatTile({
    required this.chat,
    required this.onTap,
    required this.onLongPressAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return _Pressable(
      onTap: onTap,
      onLongPressStart: (d) => onLongPressAt(d.globalPosition),
      child: GlassSurface(
        borderRadius: 18,
        blurSigma: 14,
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.12),
        child: Row(
          children: [
            RenAvatar(
              url: chat.user.avatarUrl,
              name: chat.user.name,
              isOnline: chat.user.isOnline,
              size: 44,
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

class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;

  const _Pressable({required this.child, this.onTap, this.onLongPressStart});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.985 : 1.0;
    final opacity = _pressed ? 0.92 : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      onLongPressStart: (d) {
        _setPressed(true);
        widget.onLongPressStart?.call(d);
      },
      onLongPressEnd: (_) => _setPressed(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        scale: scale,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          opacity: opacity,
          child: widget.child,
        ),
      ),
    );
  }
}
