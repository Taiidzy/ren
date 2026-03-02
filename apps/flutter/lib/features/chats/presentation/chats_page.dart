import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/features/chats/presentation/controllers/chats_chat_actions_controller.dart';
import 'package:ren/features/chats/presentation/controllers/chats_realtime_coordinator.dart';
import 'package:ren/features/chats/presentation/controllers/chats_top_banner_controller.dart';
import 'package:ren/features/chats/presentation/controllers/chats_user_search_controller.dart';
import 'package:ren/features/chats/presentation/chat_page.dart';
import 'package:ren/features/chats/presentation/widgets/chat_group_channel_sheets.dart';
import 'package:ren/features/profile/presentation/profile_menu_page.dart';

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/providers/notifications_settings.dart';
import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/core/notifications/local_notifications.dart';

import 'package:ren/shared/widgets/background.dart';
import 'package:ren/shared/widgets/adaptive_page_route.dart';
import 'package:ren/shared/widgets/avatar.dart';
import 'package:ren/shared/widgets/skeleton.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';
import 'package:ren/shared/widgets/glass_confirm_dialog.dart';
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
  late final ChatsRealtimeCoordinator _realtimeCoordinator;
  final TextEditingController _searchCtrl = TextEditingController();
  late final ChatsChatActionsController _chatActionsController;
  late final ChatsTopBannerController _topBannerController;
  late final ChatsUserSearchController _userSearchController;
  String _query = '';
  List<ChatUser> _userResults = const [];
  bool _isSearchingUsers = false;
  String? _userSearchError;
  int _myUserId = 0;

  bool _isForeground = true;
  int? _currentOpenChatId;
  Timer? _realtimeSyncDebounce;

  Future<void> _reloadChats() async {
    await _syncChats();
  }

  Future<void> _loadMyUserId() async {
    final v = await SecureStorage.readKey(Keys.userId);
    _myUserId = int.tryParse(v ?? '') ?? 0;
  }

  String _avatarUrl(String avatarPath) {
    final p = avatarPath.trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    final normalized = p.startsWith('/') ? p.substring(1) : p;
    return '${Apiurl.api}/avatars/$normalized';
  }

  void _rebuildChatIndexFromCurrentChats() {
    _chatIndex
      ..clear()
      ..addEntries(
        _chats
            .map((c) => MapEntry(int.tryParse(c.id) ?? 0, c))
            .where((e) => e.key > 0),
      );
  }

  ChatPreview _placeholderChatFromRealtime({
    required int chatId,
    required String kind,
    String? title,
  }) {
    final normalizedKind = kind.trim().toLowerCase().isEmpty
        ? 'group'
        : kind.trim().toLowerCase();
    final rawTitle = (title ?? '').trim();
    final name = rawTitle.isNotEmpty
        ? rawTitle
        : (normalizedKind == 'channel'
              ? 'Новый канал'
              : (normalizedKind == 'private' ? 'Новый чат' : 'Новая группа'));
    return ChatPreview(
      id: chatId.toString(),
      peerId: null,
      kind: normalizedKind,
      user: ChatUser(
        id: '0',
        name: name,
        nickname: null,
        avatarUrl: '',
        isOnline: false,
      ),
      isFavorite: false,
      lastMessage: '',
      lastMessageAt: DateTime.now(),
      unreadCount: 0,
      myRole: 'member',
      lastMessageIsMine: false,
      lastMessageIsPending: false,
      lastMessageIsDelivered: false,
      lastMessageIsRead: false,
    );
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
          x.unreadCount != y.unreadCount ||
          x.myRole != y.myRole ||
          x.lastMessageIsMine != y.lastMessageIsMine ||
          x.lastMessageIsPending != y.lastMessageIsPending ||
          x.lastMessageIsDelivered != y.lastMessageIsDelivered ||
          x.lastMessageIsRead != y.lastMessageIsRead ||
          x.lastMessageAt.millisecondsSinceEpoch !=
              y.lastMessageAt.millisecondsSinceEpoch) {
        return true;
      }
    }
    return false;
  }

  Future<void> _openChat(ChatPreview chat) async {
    final chatId = int.tryParse(chat.id) ?? 0;
    if (chatId > 0 && mounted) {
      setState(() {
        _currentOpenChatId = chatId;
        _chats = _chats
            .map((c) => c.id == chat.id ? c.copyWith(unreadCount: 0) : c)
            .toList(growable: false);
      });
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(adaptivePageRoute((_) => ChatPage(chat: chat)));
    if (!mounted) return;
    setState(() {
      _currentOpenChatId = null;
    });
    await _syncChats();
  }

  Future<void> _handleCreatedChat(ChatPreview chat) async {
    if (!mounted) return;
    await _reloadChats();
    if (!mounted) return;
    await _openChat(chat);
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

  void _onSearchTextChanged() {
    _userSearchController.onTextChanged(_searchCtrl.text);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _realtimeCoordinator = ChatsRealtimeCoordinator(
      context.read<RealtimeClient>(),
    );
    _chatActionsController = ChatsChatActionsController(
      context.read<ChatsRepository>(),
    );
    _topBannerController = ChatsTopBannerController();
    _userSearchController = ChatsUserSearchController(
      repo: context.read<ChatsRepository>(),
      onChanged: (snapshot) {
        if (!mounted) return;
        setState(() {
          _query = snapshot.query;
          _isSearchingUsers = snapshot.isSearching;
          _userSearchError = snapshot.error;
          _userResults = snapshot.users;
        });
      },
    );
    unawaited(_loadMyUserId());
    unawaited(_loadChatsOfflineFirst());
    _searchCtrl.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeSyncDebounce?.cancel();
    _topBannerController.dispose();
    _searchCtrl.removeListener(_onSearchTextChanged);
    _userSearchController.dispose();
    _searchCtrl.dispose();
    unawaited(_realtimeCoordinator.dispose());
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
    unawaited(HapticFeedback.mediumImpact());
    _topBannerController.show(
      context: context,
      title: title,
      body: body,
      avatarUrl: avatarUrl,
      avatarName: avatarName,
      onTap: onTap,
      duration: duration,
    );
  }

  Future<void> _showChatActionsAt(
    ChatPreview chat,
    Offset globalPosition,
  ) async {
    final chatId = int.tryParse(chat.id) ?? 0;
    if (chatId <= 0) return;
    final isGroupOrChannel = _isGroupOrChannel(chat);
    final isOwner = _isOwner(chat);

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
        if (isGroupOrChannel && isOwner) ...[
          const RenContextMenuEntry.divider(),
          RenContextMenuEntry.action(
            RenContextMenuAction<String>(
              icon: const Icon(Icons.edit_rounded, size: 20),
              label: 'Редактировать',
              value: 'edit_chat',
            ),
          ),
        ],
        const RenContextMenuEntry.divider(),
        RenContextMenuEntry.action(
          RenContextMenuAction<String>(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: 20),
            label: isGroupOrChannel ? 'Выйти' : 'Удалить чат',
            danger: true,
            value: 'leave_or_delete',
          ),
        ),
        if (isGroupOrChannel && isOwner)
          RenContextMenuEntry.action(
            RenContextMenuAction<String>(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: 20),
              label: 'Удалить чат для всех',
              danger: true,
              value: 'delete_for_all',
            ),
          ),
      ],
    );

    if (!mounted) return;
    if (action == null) return;

    if (action == 'favorite') {
      await _handleFavoriteAction(chat);
      return;
    }

    if (action == 'edit_chat') {
      await _handleEditAction(chat);
      return;
    }

    if (action == 'leave_or_delete' || action == 'delete_for_all') {
      await _handleDeleteAction(
        chat: chat,
        isGroupOrChannel: isGroupOrChannel,
        isDeleteForAll: action == 'delete_for_all',
      );
    }
  }

  bool _isGroupOrChannel(ChatPreview chat) {
    final kind = chat.kind.trim().toLowerCase();
    return kind == 'group' || kind == 'channel';
  }

  bool _isOwner(ChatPreview chat) {
    return chat.myRole.trim().toLowerCase() == 'owner';
  }

  Future<void> _handleFavoriteAction(ChatPreview chat) async {
    try {
      await _chatActionsController.toggleFavorite(chat);
      await _reloadChats();
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, e.toString(), kind: GlassSnackKind.error);
    }
  }

  Future<void> _handleEditAction(ChatPreview chat) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditGroupChannelSheet(chat: chat),
    );
    if (updated == true) {
      await _reloadChats();
    }
  }

  Future<void> _handleDeleteAction({
    required ChatPreview chat,
    required bool isGroupOrChannel,
    required bool isDeleteForAll,
  }) async {
    final confirm = await _showDeleteChatConfirmDialog(
      isGroupOrChannel: isGroupOrChannel,
      isDeleteForAll: isDeleteForAll,
    );
    if (confirm != true || !mounted) return;

    try {
      await _chatActionsController.deleteOrLeaveChat(
        chat: chat,
        forAll: isDeleteForAll,
      );
      await _reloadChats();
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, e.toString(), kind: GlassSnackKind.error);
    }
  }

  Future<bool?> _showDeleteChatConfirmDialog({
    required bool isGroupOrChannel,
    required bool isDeleteForAll,
  }) {
    return GlassOverlays.showGlassDialog<bool>(
      context,
      builder: (dctx) {
        return GlassConfirmDialog(
          title: isDeleteForAll
              ? 'Удалить чат для всех?'
              : (isGroupOrChannel ? 'Выйти из чата?' : 'Удалить чат?'),
          text: isDeleteForAll
              ? 'Чат/канал будет удалён для всех участников. Действие необратимо.'
              : (isGroupOrChannel
                    ? 'Вы покинете этот чат/канал. Вернуться можно только после повторного добавления.'
                    : 'Чат будет удалён из вашего списка.'),
          confirmLabel: isDeleteForAll
              ? 'Удалить для всех'
              : (isGroupOrChannel ? 'Выйти' : 'Удалить'),
          onConfirm: () => Navigator.of(dctx).pop(true),
        );
      },
    );
  }

  Future<void> _ensureRealtime(List<ChatPreview> chats) async {
    _chatIndex
      ..clear()
      ..addEntries(
        chats
            .map((c) => MapEntry(int.tryParse(c.id) ?? 0, c))
            .where((e) => e.key > 0),
      );

    await _realtimeCoordinator.ensureConnected(
      chats: chats,
      onEvent: _handleRealtimeEvent,
    );
  }

  Future<void> _handleRealtimeEvent(RealtimeEvent evt) async {
    if (!_mounted) return;
    _handleMessageSyncEvents(evt);
    switch (evt.type) {
      case 'connection':
        _handleConnectionEvent(evt);
        return;
      case 'presence':
        _handlePresenceEvent(evt);
        return;
      case 'chat_created':
        await _handleChatCreatedEvent(evt);
        return;
      case 'member_added':
      case 'member_removed':
      case 'member_role_changed':
        await _handleMemberEvent(evt);
        return;
      case 'chat_updated':
        unawaited(_syncChats());
        return;
      case 'profile_updated':
        _handleProfileUpdatedEvent(evt);
        return;
      case 'message_new':
        await _handleIncomingMessageEvent(evt);
        return;
      default:
        return;
    }
  }

  bool get _mounted => mounted;

  void _scheduleRealtimeChatsSync() {
    _realtimeSyncDebounce?.cancel();
    _realtimeSyncDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      unawaited(_syncChats());
    });
  }

  void _handleMessageSyncEvents(RealtimeEvent evt) {
    final eventType = evt.type;
    if (eventType == 'message_new' ||
        eventType == 'message_updated' ||
        eventType == 'message_deleted' ||
        eventType == 'message_delivered' ||
        eventType == 'message_read') {
      // While a chat is open, ChatPage keeps state fresh via WS and local cache.
      // Avoid extra chat-list GET requests on every message event.
      if (_currentOpenChatId != null) return;

      // Ignore self-echo message_new: local preview already updates on send/open chat.
      if (eventType == 'message_new') {
        final msg = evt.data['message'];
        if (msg is Map) {
          final sender = (msg['sender_id'] is int)
              ? msg['sender_id'] as int
              : int.tryParse('${msg['sender_id'] ?? ''}') ?? 0;
          if (_myUserId > 0 && sender == _myUserId) return;
        }
      }
      _scheduleRealtimeChatsSync();
    }
  }

  void _handleConnectionEvent(RealtimeEvent evt) {
    final reconnected = evt.data['reconnected'] == true;
    if (reconnected) {
      unawaited(_syncChats());
    }
  }

  void _handlePresenceEvent(RealtimeEvent evt) {
    final userId = evt.data['user_id'];
    final status = (evt.data['status'] as String?) ?? '';
    final idStr = '$userId';
    final isOnline = status == 'online';
    if (_online[idStr] == isOnline) return;
    setState(() {
      _online[idStr] = isOnline;
    });
  }

  Future<void> _handleChatCreatedEvent(RealtimeEvent evt) async {
    final chatId = int.tryParse(
      '${evt.data['chat_id'] ?? evt.data['chatId'] ?? 0}',
    );
    final kind = '${evt.data['kind'] ?? 'group'}';
    final title = (evt.data['title'] as String?)?.trim();
    final createdBy = int.tryParse(
      '${evt.data['created_by'] ?? evt.data['createdBy'] ?? 0}',
    );

    if (chatId != null && chatId > 0 && _chatIndex[chatId] == null) {
      setState(() {
        final preview = _placeholderChatFromRealtime(
          chatId: chatId,
          kind: kind,
          title: title,
        );
        _chats = [preview, ..._chats];
        _rebuildChatIndexFromCurrentChats();
      });
    }

    if ((createdBy ?? 0) != _myUserId) {
      showGlassSnack(
        context,
        'Добавлен новый чат: ${(title != null && title.isNotEmpty) ? title : "Без названия"}',
        kind: GlassSnackKind.info,
      );
    }
    unawaited(_syncChats());
  }

  Future<void> _handleMemberEvent(RealtimeEvent evt) async {
    final chatId = int.tryParse(
      '${evt.data['chat_id'] ?? evt.data['chatId'] ?? 0}',
    );
    final targetUserId = int.tryParse(
      '${evt.data['user_id'] ?? evt.data['userId'] ?? 0}',
    );
    if (chatId == null ||
        chatId <= 0 ||
        targetUserId == null ||
        targetUserId != _myUserId) {
      unawaited(_syncChats());
      return;
    }

    if (evt.type == 'member_added' && _chatIndex[chatId] == null) {
      setState(() {
        final preview = _placeholderChatFromRealtime(
          chatId: chatId,
          kind: 'group',
          title: null,
        );
        _chats = [preview, ..._chats];
        _rebuildChatIndexFromCurrentChats();
      });
      showGlassSnack(context, 'Вас добавили в чат', kind: GlassSnackKind.info);
    } else if (evt.type == 'member_removed') {
      setState(() {
        _chats = _chats
            .where((c) => (int.tryParse(c.id) ?? 0) != chatId)
            .toList(growable: false);
        _rebuildChatIndexFromCurrentChats();
      });
      showGlassSnack(context, 'Вас удалили из чата', kind: GlassSnackKind.info);
    } else if (evt.type == 'member_role_changed') {
      showGlassSnack(
        context,
        'Ваша роль в чате обновлена',
        kind: GlassSnackKind.info,
      );
    }
    unawaited(_syncChats());
  }

  void _handleProfileUpdatedEvent(RealtimeEvent evt) {
    final userDyn = evt.data['user'];
    if (userDyn is! Map) return;
    final user = (userDyn is Map<String, dynamic>)
        ? userDyn
        : Map<String, dynamic>.fromEntries(
            userDyn.entries.map((e) => MapEntry(e.key.toString(), e.value)),
          );
    final uid = (user['id'] is int)
        ? user['id'] as int
        : int.tryParse('${user['id'] ?? ''}') ?? 0;
    if (uid <= 0) return;

    final username = ((user['username'] as String?) ?? '').trim();
    final nickname = ((user['nickname'] as String?) ?? '').trim();
    final avatarRaw = ((user['avatar'] as String?) ?? '').trim();
    final avatarUrl = avatarRaw.isEmpty ? '' : _avatarUrl(avatarRaw);
    setState(() {
      _chats = _chats
          .map((c) {
            if ((c.peerId ?? 0) != uid) return c;
            return c.copyWith(
              user: c.user.copyWith(
                name: nickname.isNotEmpty
                    ? nickname
                    : (username.isNotEmpty ? username : c.user.name),
                nickname: nickname.isNotEmpty ? nickname : null,
                avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : c.user.avatarUrl,
              ),
            );
          })
          .toList(growable: false);
      _rebuildChatIndexFromCurrentChats();
    });
  }

  Future<void> _handleIncomingMessageEvent(RealtimeEvent evt) async {
    final repo = context.read<ChatsRepository>();
    final chatIdDyn = evt.data['chat_id'] ?? evt.data['chatId'];
    final chatId = (chatIdDyn is int)
        ? chatIdDyn
        : int.tryParse('$chatIdDyn') ?? 0;
    if (chatId <= 0) return;

    final messageData = evt.data['message'];
    if (messageData is! Map) return;

    final message = (messageData is Map<String, dynamic>)
        ? messageData
        : Map<String, dynamic>.fromEntries(
            messageData.entries.map((e) => MapEntry(e.key.toString(), e.value)),
          );

    final senderId = (message['sender_id'] is int)
        ? message['sender_id'] as int
        : int.tryParse('${message['sender_id'] ?? ''}') ?? 0;
    if (_myUserId > 0 && senderId == _myUserId) return;
    if (_currentOpenChatId == chatId) return;

    final decoded = await repo.decryptIncomingWsMessageFull(message: message);
    final hasAttachments = decoded.attachments.isNotEmpty;
    final chat = _chatIndex[chatId];
    final title = (chat?.user.name ?? '').trim().isNotEmpty
        ? (chat!.user.name)
        : 'Новое сообщение';
    final body = decoded.text.trim().isNotEmpty
        ? decoded.text.trim()
        : (hasAttachments ? 'Вложение' : 'Сообщение');

    final notificationsSettings = context.read<NotificationsSettings>();
    if (_isForeground) {
      if (notificationsSettings.inAppSoundEnabled) {
        SystemSound.play(SystemSoundType.click);
      }
      if (notificationsSettings.inAppBannersEnabled) {
        _showTopGlassBanner(
          title: title,
          body: body,
          avatarUrl: chat?.user.avatarUrl ?? '',
          avatarName: chat?.user.name ?? title,
          onTap: () {
            final c = _chatIndex[chatId];
            if (c == null) return;
            _openChat(c);
          },
        );
      }
      return;
    }

    await LocalNotifications.instance.showMessageNotification(
      chatId: chatId,
      title: title,
      body: body,
      avatarUrl: chat?.user.avatarUrl,
      senderName: chat?.user.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final baseInk = isDark ? Colors.white : Colors.black;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final appBarSearchHorizontalInset = (screenWidth * 0.16)
        .clamp(16.0, 96.0)
        .toDouble();
    final pageHorizontalPadding = screenWidth < 360 ? 12.0 : 16.0;
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
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Чаты',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: isSyncing
                          ? SizedBox(
                              key: const ValueKey('syncing'),
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.8,
                                ),
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
              padding: EdgeInsets.fromLTRB(
                appBarSearchHorizontalInset,
                0,
                appBarSearchHorizontalInset,
                4,
              ),
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
                    (c) => c.copyWith(
                      user: c.user.copyWith(
                        isOnline: _online[c.user.id] ?? c.user.isOnline,
                      ),
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
                padding: EdgeInsets.fromLTRB(
                  pageHorizontalPadding,
                  14,
                  pageHorizontalPadding,
                  0,
                ),
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
                          : (_query.trim().isEmpty
                                ? ListView.separated(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    itemCount: visibleChats.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final chat = visibleChats[index];
                                      return _ChatTile(
                                        chat: chat,
                                        unreadCount: chat.unreadCount,
                                        onLongPressAt: (pos) =>
                                            _showChatActionsAt(chat, pos),
                                        onTap: () => _openChat(chat),
                                      );
                                    },
                                  )
                                : ListView(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: GlassSurface(
                                              borderRadius: 12,
                                              blurSigma: 8,
                                              borderColor: baseInk.withOpacity(
                                                isDark ? 0.14 : 0.08,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                onTap: () {
                                                  GlassOverlays.showGlassBottomSheet(
                                                    context,
                                                    builder: (_) =>
                                                        CreateGroupChannelSheet(
                                                          kind: 'group',
                                                          initialTitle: _query,
                                                          onCreated:
                                                              _handleCreatedChat,
                                                        ),
                                                  );
                                                },
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.group_add_rounded,
                                                      size: 18,
                                                      color: theme
                                                          .colorScheme
                                                          .onSurface,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Flexible(
                                                      child: Text(
                                                        'Создать группу',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: GlassSurface(
                                              borderRadius: 12,
                                              blurSigma: 8,
                                              borderColor: baseInk.withOpacity(
                                                isDark ? 0.14 : 0.08,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                onTap: () {
                                                  GlassOverlays.showGlassBottomSheet(
                                                    context,
                                                    builder: (_) =>
                                                        CreateGroupChannelSheet(
                                                          kind: 'channel',
                                                          initialTitle: _query,
                                                          onCreated:
                                                              _handleCreatedChat,
                                                        ),
                                                  );
                                                },
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.campaign_rounded,
                                                      size: 18,
                                                      color: theme
                                                          .colorScheme
                                                          .onSurface,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Flexible(
                                                      child: Text(
                                                        'Создать канал',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'Чаты',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                      for (final chat in visibleChats) ...[
                                        _ChatTile(
                                          chat: chat,
                                          unreadCount: chat.unreadCount,
                                          onLongPressAt: (pos) =>
                                              _showChatActionsAt(chat, pos),
                                          onTap: () => _openChat(chat),
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                      Divider(
                                        height: 28,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.18),
                                      ),
                                      Text(
                                        'Пользователи',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                      if (_isSearchingUsers) ...[
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
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
                                                  color:
                                                      theme.colorScheme.error,
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
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
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
                                                  .where(
                                                    (c) => c.peerId == peerId,
                                                  )
                                                  .cast<ChatPreview?>()
                                                  .firstWhere(
                                                    (c) => c != null,
                                                    orElse: () => null,
                                                  );

                                              if (existing != null) {
                                                if (!context.mounted) return;
                                                _openChat(existing);
                                                return;
                                              }

                                              try {
                                                final repo = context
                                                    .read<ChatsRepository>();
                                                final chat = await repo
                                                    .createPrivateChat(
                                                      peerId,
                                                      fallbackPeerName:
                                                          user.name,
                                                      fallbackPeerAvatarUrl:
                                                          user.avatarUrl,
                                                    );
                                                if (!context.mounted) return;
                                                await _reloadChats();
                                                if (!context.mounted) return;
                                                _openChat(chat);
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
                                  )),
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
  final int unreadCount;
  final VoidCallback onTap;
  final ValueChanged<Offset> onLongPressAt;

  const _ChatTile({
    required this.chat,
    this.unreadCount = 0,
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: GlassSurface(
          borderRadius: 18,
          blurSigma: 14,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                    Row(
                      children: [
                        if (chat.lastMessageIsMine || chat.lastMessageIsPending)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              chat.lastMessageIsPending
                                  ? Icons.schedule_rounded
                                  : (chat.lastMessageIsRead ||
                                            chat.lastMessageIsDelivered
                                        ? Icons.done_all_rounded
                                        : Icons.done_rounded),
                              size: 13,
                              color: chat.lastMessageIsPending
                                  ? theme.colorScheme.onSurface.withOpacity(
                                      0.55,
                                    )
                                  : (chat.lastMessageIsRead
                                        ? theme.colorScheme.primary.withOpacity(
                                            0.92,
                                          )
                                        : (chat.lastMessageIsDelivered
                                              ? theme.colorScheme.onSurface
                                                    .withOpacity(0.65)
                                              : theme.colorScheme.onSurface
                                                    .withOpacity(0.55))),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            chat.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.70,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(chat.lastMessageAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.60),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: unreadCount > 0
                        ? Container(
                            key: ValueKey<int>(unreadCount),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(
                                0.92,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            constraints: const BoxConstraints(minWidth: 22),
                            alignment: Alignment.center,
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          )
                        : const SizedBox(
                            key: ValueKey('no_unread'),
                            width: 22,
                            height: 16,
                          ),
                  ),
                ],
              ),
            ],
          ),
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
