import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/features/chats/presentation/controllers/chat_attachments_picker_controller.dart';
import 'package:ren/features/chats/presentation/controllers/chat_attachments_preparer.dart';
import 'package:ren/features/chats/presentation/controllers/chat_pending_attachments_controller.dart';
import 'package:ren/features/chats/presentation/controllers/chat_page_realtime_coordinator.dart';
import 'package:ren/shared/widgets/background.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';

import 'package:ren/features/chats/presentation/widgets/chat_attachment_viewer_sheet.dart';
import 'package:ren/features/chats/presentation/widgets/chat_input_bar.dart';
import 'package:ren/features/chats/presentation/widgets/chat_message_context_menu.dart';
import 'package:ren/features/chats/presentation/widgets/chat_message_bubble.dart';
import 'package:ren/features/chats/presentation/widgets/chat_members_sheet_body.dart';
import 'package:ren/features/chats/presentation/widgets/chat_page_app_bar.dart';
import 'package:ren/features/chats/presentation/widgets/chat_pending_attachment.dart';
import 'package:ren/features/chats/presentation/widgets/chat_skeleton_message_bubble.dart';
import 'package:ren/features/chats/presentation/widgets/chat_recorder_ui.dart';
import 'package:ren/features/chats/presentation/widgets/voice_message_bubble.dart';
import 'package:ren/features/chats/presentation/widgets/square_video_bubble.dart';

class ChatPage extends StatefulWidget {
  final ChatPreview chat;

  const ChatPage({super.key, required this.chat});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const int _maxSingleAttachmentBytes = 25 * 1024 * 1024;
  static const int _maxPendingAttachmentsBytes = 80 * 1024 * 1024;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  static final Map<String, double> _savedScrollOffsetByChatId =
      <String, double>{};
  final Map<String, GlobalKey> _messageItemKeys = <String, GlobalKey>{};
  bool _didApplyInitialScroll = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  final List<ChatMessage> _messages = [];
  final Map<String, ChatMessage> _messageById = {};

  ChatMessage? _replyTo;
  ChatMessage? _editing;

  final ValueNotifier<String?> _pressedMessageIdN = ValueNotifier<String?>(
    null,
  );

  final ValueNotifier<bool> _selectionModeN = ValueNotifier<bool>(false);
  final ValueNotifier<Set<String>> _selectedMessageIdsN =
      ValueNotifier<Set<String>>(<String>{});
  late final Listenable _selectionListenable = Listenable.merge([
    _selectionModeN,
    _selectedMessageIdsN,
  ]);

  late final ChatAttachmentsPickerController _attachmentsPickerController =
      ChatAttachmentsPickerController();
  static const ChatAttachmentsPreparer _attachmentsPreparer =
      ChatAttachmentsPreparer();

  late final ChatPendingAttachmentsController _pendingController =
      ChatPendingAttachmentsController(
        maxSingleAttachmentBytes: _maxSingleAttachmentBytes,
        maxPendingAttachmentsBytes: _maxPendingAttachmentsBytes,
      );
  bool _isSendingMessage = false;

  int? _myUserId;

  bool _peerOnline = false;
  bool _peerTyping = false;
  String _peerName = '';
  String _peerAvatarUrl = '';
  String _myRoleInChat = 'member';
  bool _canSendInCurrentChat = true;
  Timer? _typingDebounce;
  Timer? _markReadDebounce;
  Timer? _markDeliveredDebounce;
  int _lastReadMarkedMessageId = 0;
  int _lastDeliveredMarkedMessageId = 0;
  String? _firstUnreadMessageId;
  bool _didInitUnreadDividerAnchor = false;

  bool _isAtBottom = true;
  int _newMessagesWhileAway = 0;

  int _scrollToBottomRequestId = 0;

  double _lastViewInsetsBottom = 0;

  RealtimeClient? _rt;
  late final ChatPageRealtimeCoordinator _realtimeCoordinator;

  Timer? _loadOlderDebounce;
  late final ValueNotifier<bool> _messagesSyncingN;
  late final ChatsRepository _repo;
  bool get _isPrivateChat => widget.chat.kind.trim().toLowerCase() == 'private';

  bool _showVideoRecordingOverlay = false;
  String _videoRecordingDurationText = '0:00';
  bool _videoFlashEnabled = false;
  bool _videoUseFrontCamera = false;
  bool _videoRecordingLocked = false;
  CameraController? _videoCameraController;
  Future<bool> Function(bool enabled)? _setVideoTorch;
  Future<bool> Function(bool useFront)? _setVideoUseFrontCamera;
  VoidCallback? _cancelVideoRecording;
  VoidCallback? _stopVideoRecording;
  late final AnimationController _videoProgressController;
  late final AnimationController _videoLockedTransition;
  late final AnimationController _videoPulse;
  late final AnimationController _jumpBadgePulse;

  void _setVideoRecordingOverlay({required bool show}) {
    if (_showVideoRecordingOverlay == show) return;
    if (!mounted) return;
    setState(() {
      _showVideoRecordingOverlay = show;
      if (!show) {
        _videoRecordingDurationText = '0:00';
        _videoFlashEnabled = false;
        _videoUseFrontCamera = false;
        _videoRecordingLocked = false;
        _videoCameraController = null;
      }
    });

    if (show) {
      _videoProgressController
        ..reset()
        ..forward();
    } else {
      _videoProgressController
        ..stop()
        ..reset();
    }

    if (!show) {
      _videoLockedTransition
        ..stop()
        ..value = 0;
    }
  }

  void _onVideoRecordingDurationChanged(String text) {
    if (!_showVideoRecordingOverlay || !mounted) return;
    if (_videoRecordingDurationText == text) return;
    setState(() {
      _videoRecordingDurationText = text;
    });
  }

  void _onVideoRecordingLockedChanged(bool locked) {
    if (!mounted || _videoRecordingLocked == locked) return;
    setState(() {
      _videoRecordingLocked = locked;
    });

    if (locked) {
      _videoLockedTransition.forward();
    } else {
      _videoLockedTransition.reverse();
    }
  }

  void _onVideoControllerChanged(CameraController? controller) {
    if (!mounted) return;
    if (identical(_videoCameraController, controller)) return;
    setState(() {
      _videoCameraController = controller;
    });
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  bool _canAttachFileSize(int sizeBytes) {
    final error = _pendingController.validateNextAttachmentSize(sizeBytes);
    if (error != null) {
      showGlassSnack(context, error, kind: GlassSnackKind.error);
      return false;
    }
    return true;
  }

  String _avatarUrl(String avatarPath) {
    final p = avatarPath.trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    final normalized = p.startsWith('/') ? p.substring(1) : p;
    return '${Apiurl.api}/avatars/$normalized';
  }

  void _reindexMessages() {
    _messageById.clear();
    final ids = <String>{};
    for (final m in _messages) {
      _messageById[m.id] = m;
      ids.add(m.id);
    }
    _messageItemKeys.removeWhere((id, _) => !ids.contains(id));
  }

  void _recomputeUnreadDividerAnchor() {
    final unread = widget.chat.unreadCount;
    if (unread <= 0 || _messages.isEmpty) {
      _firstUnreadMessageId = null;
      return;
    }

    final startIndex = (_messages.length - unread).clamp(
      0,
      _messages.length - 1,
    );
    for (var i = startIndex; i < _messages.length; i++) {
      final mid = int.tryParse(_messages[i].id) ?? 0;
      if (mid > 0) {
        _firstUnreadMessageId = _messages[i].id;
        return;
      }
    }

    _firstUnreadMessageId = null;
  }

  void _clearUnreadDividerIfCoveredByReadCursor(int lastReadMessageId) {
    final anchorId = int.tryParse(_firstUnreadMessageId ?? '') ?? 0;
    if (anchorId <= 0) return;
    if (lastReadMessageId >= anchorId) {
      _firstUnreadMessageId = null;
    }
  }

  void _initUnreadDividerAnchorOnce() {
    if (_didInitUnreadDividerAnchor) return;
    _didInitUnreadDividerAnchor = true;
    _recomputeUnreadDividerAnchor();
  }

  String _messageSummary(ChatMessage m) {
    final t = m.text.trim();
    if (t.isNotEmpty) return t;
    if (m.attachments.isNotEmpty) {
      final a = m.attachments.first;
      if (a.isImage) return 'Фото';
      if (a.isVideo) return 'Видео';
      if (a.mimetype.startsWith('audio/')) return 'Голосовое сообщение';
      final name = a.filename.trim();
      return name.isNotEmpty ? name : 'Файл';
    }
    return '';
  }

  bool _isVoiceMessage(ChatMessage msg) {
    if (msg.attachments.length != 1) return false;
    final att = msg.attachments.first;
    return att.mimetype.startsWith('audio/');
  }

  bool _isSquareVideoMessage(ChatMessage msg) {
    if (msg.attachments.length != 1) return false;
    final att = msg.attachments.first;
    if (!att.mimetype.startsWith('video/')) return false;
    // Проверяем, что это квадратик по имени файла (начинается с video_)
    final filename = att.filename.toLowerCase();
    return filename.startsWith('video_') || filename.startsWith('square_');
  }

  Future<void> _ensureWsReady(int chatId) async {
    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;
    if (!rt.isConnected) {
      await rt.connect();
    }
    rt.joinChat(chatId);
  }

  ChatMessage? _findMessageById(String? id) {
    if (id == null || id.isEmpty) return null;
    return _messageById[id];
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildMessageBubble({
    required ChatMessage msg,
    required String? replyPreview,
    required bool isDark,
  }) {
    if (_isVoiceMessage(msg)) {
      final audioPath = msg.attachments.first.localPath;
      return VoiceMessageBubble(
        audioPath: audioPath,
        timeLabel: _formatTime(msg.sentAt),
        isMe: msg.isMe,
        isDelivered: msg.isDelivered,
        isRead: msg.isRead,
        isPending: msg.id.startsWith('local_'),
        isDark: isDark,
      );
    }

    if (_isSquareVideoMessage(msg)) {
      final videoPath = msg.attachments.first.localPath;
      return SquareVideoBubble(
        videoPath: videoPath,
        timeLabel: _formatTime(msg.sentAt),
        isMe: msg.isMe,
        isDelivered: msg.isDelivered,
        isRead: msg.isRead,
        isPending: msg.id.startsWith('local_'),
        isDark: isDark,
      );
    }

    return ChatMessageBubble(
      replyPreview: (replyPreview != null && replyPreview.isNotEmpty)
          ? replyPreview
          : null,
      text: msg.text,
      attachments: msg.attachments,
      timeLabel: _formatTime(msg.sentAt),
      isMe: msg.isMe,
      isDelivered: msg.isDelivered,
      isRead: msg.isRead,
      isPending: msg.id.startsWith('local_'),
      isDark: isDark,
      onOpenAttachment: (a) => _openAttachmentSheet(a),
    );
  }

  List<ChatAttachment> _allChatAttachments() {
    final out = <ChatAttachment>[];
    for (final m in _messages) {
      if (m.attachments.isEmpty) continue;
      out.addAll(m.attachments);
    }
    return out;
  }

  Future<void> _openAttachmentSheet(ChatAttachment tapped) async {
    final items = _allChatAttachments();
    if (items.isEmpty) return;

    final initial = items.indexWhere((a) => a.localPath == tapped.localPath);
    final initialIndex = (initial >= 0) ? initial : 0;

    await GlassOverlays.showGlassBottomSheet<void>(
      context,
      builder: (ctx) {
        return ChatAttachmentViewerSheet(
          items: items,
          initialIndex: initialIndex,
        );
      },
    );
  }

  Future<void> _openMembersSheet() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;
    final kind = widget.chat.kind.trim().toLowerCase();
    if (kind == 'private') {
      showGlassSnack(
        context,
        'Для private-чата список участников недоступен',
        kind: GlassSnackKind.info,
      );
      return;
    }

    final myId = _myUserId ?? await _readMyUserId();
    if (!mounted) return;
    await GlassOverlays.showGlassBottomSheet<void>(
      context,
      builder: (_) => ChatMembersSheetBody(
        chatId: chatId,
        chatKind: kind,
        myUserId: myId,
        repo: _repo,
      ),
    );
    await _refreshMyChatRole();
  }

  Future<void> _refreshMyChatRole() async {
    final kind = widget.chat.kind.trim().toLowerCase();
    if (kind != 'channel') {
      if (!mounted) return;
      setState(() {
        _myRoleInChat = 'member';
        _canSendInCurrentChat = true;
      });
      return;
    }

    final myId = _myUserId ?? await _readMyUserId();
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;
    try {
      final members = await _repo.listMembers(chatId);
      final me = members
          .where((m) => m.userId == myId)
          .cast<ChatMember?>()
          .firstWhere((m) => m != null, orElse: () => null);
      final role = (me?.role ?? 'member').trim().toLowerCase();
      final canSend = role == 'owner' || role == 'admin';
      if (!mounted) return;
      setState(() {
        _myRoleInChat = role.isEmpty ? 'member' : role;
        _canSendInCurrentChat = canSend;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _myRoleInChat = 'member';
        _canSendInCurrentChat = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    _repo = context.read<ChatsRepository>();
    _messagesSyncingN = context.read<ChatsRepository>().messagesSyncingNotifier(
      chatId,
    );
    _rt = context.read<RealtimeClient>();
    _realtimeCoordinator = ChatPageRealtimeCoordinator(_rt!);
    WidgetsBinding.instance.addObserver(this);
    _videoProgressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
    _videoLockedTransition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _videoPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    )..repeat();
    _jumpBadgePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _peerOnline = widget.chat.user.isOnline;
    _peerName = widget.chat.user.name;
    _peerAvatarUrl = widget.chat.user.avatarUrl;
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    _scrollController.addListener(_onScroll);
    _init();
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final bottom = view.viewInsets.bottom / view.devicePixelRatio;
    if (_focusNode.hasFocus && _isAtBottom && bottom != _lastViewInsetsBottom) {
      _lastViewInsetsBottom = bottom;
      _scheduleScrollToBottom(animated: false);
    } else {
      _lastViewInsetsBottom = bottom;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused) &&
        _scrollController.hasClients) {
      final offset = _scrollController.offset;
      _savedScrollOffsetByChatId[widget.chat.id] = offset;
      unawaited(_repo.saveChatScrollOffset(widget.chat.id, offset));
    }
  }

  void _scheduleScrollToBottom({required bool animated}) {
    if (_newMessagesWhileAway > 0 && mounted) {
      setState(() {
        _newMessagesWhileAway = 0;
      });
    }
    _scrollToBottomRequestId++;
    final reqId = _scrollToBottomRequestId;

    // Scroll can be requested before ListView reports correct maxScrollExtent.
    // Retry a few times after layout to ensure we end up at the bottom.
    void attempt(int left) {
      if (reqId != _scrollToBottomRequestId) return;
      _scrollToBottom(animated: animated);
      if (left <= 0) return;

      Future.delayed(const Duration(milliseconds: 60), () {
        if (!mounted) return;
        if (reqId != _scrollToBottomRequestId) return;
        if (!_scrollController.hasClients) return;
        final pos = _scrollController.position;
        if (pos.isScrollingNotifier.value) return;
        final dist = pos.maxScrollExtent - pos.pixels;
        if (dist > 8) {
          attempt(left - 1);
        }
      });
    }

    attempt(4);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final dist = pos.maxScrollExtent - pos.pixels;
    final atBottom = dist < 120;
    if (atBottom != _isAtBottom && mounted) {
      setState(() {
        _isAtBottom = atBottom;
        if (atBottom) {
          _newMessagesWhileAway = 0;
        }
      });
    }

    // Pagination: when user scrolls near top, load older messages.
    if (pos.pixels < 220) {
      _loadOlderDebounce?.cancel();
      _loadOlderDebounce = Timer(const Duration(milliseconds: 160), () {
        if (!mounted) return;
        _loadOlder();
      });
    }

    _scheduleMarkRead();
  }

  Future<void> _loadOlder() async {
    if (_loading || _loadingMore || !_hasMore) return;
    if (_messages.isEmpty) return;

    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    final beforeId = int.tryParse(_messages.first.id) ?? 0;
    if (beforeId <= 0) return;

    final repo = context.read<ChatsRepository>();

    final oldPixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    final oldMax = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    setState(() {
      _loadingMore = true;
    });

    try {
      final list = await repo.fetchMessages(
        chatId,
        limit: 50,
        beforeId: beforeId,
      );
      if (!mounted) return;

      if (list.isEmpty) {
        setState(() {
          _hasMore = false;
          _loadingMore = false;
        });
        return;
      }

      final toAdd = <ChatMessage>[];
      for (final m in list) {
        if (!_messageById.containsKey(m.id)) {
          toAdd.add(m);
        }
      }

      if (toAdd.isEmpty) {
        setState(() {
          _loadingMore = false;
        });
        return;
      }

      setState(() {
        _messages.insertAll(0, toAdd);
        _reindexMessages();
        _loadingMore = false;
      });

      // Preserve scroll position: compensate added content height.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_scrollController.hasClients) return;
        final newMax = _scrollController.position.maxScrollExtent;
        final delta = newMax - oldMax;
        final target = oldPixels + delta;
        if (target.isFinite) {
          _scrollController.jumpTo(target);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
      });
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _sendTyping(false);
    } else {
      _scheduleScrollToBottom(animated: true);
    }
  }

  void _scrollToBottom({required bool animated}) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.isScrollingNotifier.value) return;
      final target = pos.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _sendTyping(bool isTyping) {
    if (!_canSendInCurrentChat) return;
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    final rt = _rt;
    if (rt == null || !rt.isConnected) return;
    rt.typing(chatId, isTyping);
  }

  GlobalKey _messageKey(String messageId) {
    return _messageItemKeys.putIfAbsent(
      messageId,
      () => GlobalKey(debugLabel: 'msg_$messageId'),
    );
  }

  int _latestVisibleRemoteMessageId() {
    if (!_scrollController.hasClients) return 0;
    final viewportRenderObject = _scrollController
        .position
        .context
        .storageContext
        .findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.attached) {
      return 0;
    }

    final viewportRect = Offset.zero & viewportRenderObject.size;
    var maxVisibleId = 0;

    for (final msg in _messages) {
      final mid = int.tryParse(msg.id) ?? 0;
      if (mid <= 0) continue;

      final key = _messageItemKeys[msg.id];
      final ctx = key?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;

      final topLeft = box.localToGlobal(
        Offset.zero,
        ancestor: viewportRenderObject,
      );
      final rect = topLeft & box.size;
      final visible = rect.intersect(viewportRect);
      if (visible.isEmpty) continue;

      final minVisibleHeight = math.max(20.0, rect.height * 0.35);
      if (visible.height < minVisibleHeight) continue;

      if (mid > maxVisibleId) {
        maxVisibleId = mid;
      }
    }

    return maxVisibleId;
  }

  int _latestIncomingRemoteMessageId() {
    var maxId = 0;
    for (final msg in _messages) {
      if (msg.isMe) continue;
      final id = int.tryParse(msg.id) ?? 0;
      if (id > maxId) {
        maxId = id;
      }
    }
    return maxId;
  }

  bool _tryApplyUnreadAnchorInitialPosition() {
    final anchorId = _firstUnreadMessageId;
    if (anchorId == null || anchorId.isEmpty) return false;
    final anchorIndex = _messages.indexWhere((m) => m.id == anchorId);
    if (anchorIndex < 0 || _messages.length <= 1) return false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final ratio = anchorIndex / (_messages.length - 1);
      final coarse = (pos.maxScrollExtent * ratio).clamp(
        0.0,
        pos.maxScrollExtent,
      );
      _scrollController.jumpTo(coarse);

      final anchorCtx = _messageItemKeys[anchorId]?.currentContext;
      if (anchorCtx != null) {
        Scrollable.ensureVisible(
          anchorCtx,
          alignment: 0.18,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }

      final dist = pos.maxScrollExtent - _scrollController.offset;
      final atBottom = dist < 120;
      if (atBottom != _isAtBottom && mounted) {
        setState(() {
          _isAtBottom = atBottom;
        });
      }
    });
    return true;
  }

  void _applyInitialScrollPosition() {
    if (_didApplyInitialScroll) return;
    _didApplyInitialScroll = true;

    final savedOffset = _savedScrollOffsetByChatId[widget.chat.id];
    if (savedOffset == null) {
      final anchored = _tryApplyUnreadAnchorInitialPosition();
      if (!anchored) {
        _scheduleScrollToBottom(animated: false);
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final target = savedOffset.clamp(0.0, pos.maxScrollExtent);
      _scrollController.jumpTo(target);
      final dist = pos.maxScrollExtent - target;
      final atBottom = dist < 120;
      if (atBottom != _isAtBottom && mounted) {
        setState(() {
          _isAtBottom = atBottom;
        });
      }
    });
  }

  void _scheduleInitialReadAndDelivered() {
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      _scheduleMarkDelivered();
      _scheduleMarkRead();
    });
  }

  Future<void> _markChatReadUpToLatest() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    final latestId = _latestVisibleRemoteMessageId();
    if (latestId <= 0 || latestId <= _lastReadMarkedMessageId) return;

    try {
      final acknowledged = await _repo.markChatRead(
        chatId,
        messageId: latestId,
      );
      if (acknowledged > _lastReadMarkedMessageId) {
        _lastReadMarkedMessageId = acknowledged;
        if (mounted) {
          setState(() {
            _clearUnreadDividerIfCoveredByReadCursor(acknowledged);
          });
        } else {
          _clearUnreadDividerIfCoveredByReadCursor(acknowledged);
        }
      }
    } catch (_) {
      // ignore transient read sync failures
    }
  }

  Future<void> _markChatDeliveredUpToLatestIncoming() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    final latestIncomingId = _latestIncomingRemoteMessageId();
    if (latestIncomingId <= 0 ||
        latestIncomingId <= _lastDeliveredMarkedMessageId) {
      return;
    }

    try {
      final acknowledged = await _repo.markChatDelivered(
        chatId,
        messageId: latestIncomingId,
      );
      if (acknowledged > _lastDeliveredMarkedMessageId) {
        _lastDeliveredMarkedMessageId = acknowledged;
      }
    } catch (_) {
      // ignore transient delivery sync failures
    }
  }

  void _scheduleMarkRead() {
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      unawaited(_markChatReadUpToLatest());
    });
  }

  void _scheduleMarkDelivered() {
    _markDeliveredDebounce?.cancel();
    _markDeliveredDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      unawaited(_markChatDeliveredUpToLatestIncoming());
    });
  }

  Future<void> _ensurePersistedScrollOffsetLoaded() async {
    if (_savedScrollOffsetByChatId.containsKey(widget.chat.id)) {
      return;
    }
    try {
      final stored = await _repo.loadChatScrollOffset(widget.chat.id);
      if (stored != null && stored.isFinite) {
        _savedScrollOffsetByChatId[widget.chat.id] = stored;
      }
    } catch (_) {
      // ignore local cache read errors
    }
  }

  void _onTextChanged() {
    _typingDebounce?.cancel();

    final hasText = _controller.text.trim().isNotEmpty;
    if (!hasText) {
      _sendTyping(false);
      return;
    }

    // When user types: send true immediately, then send false after inactivity
    _sendTyping(true);

    _typingDebounce = Timer(const Duration(milliseconds: 900), () {
      _sendTyping(false);
    });
  }

  Future<void> _init() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    final repo = context.read<ChatsRepository>();
    await _ensurePersistedScrollOffsetLoaded();

    final cached = await repo.getCachedMessages(chatId);
    if (mounted && cached.isNotEmpty) {
      setState(() {
        _messages
          ..clear()
          ..addAll(cached);
        _reindexMessages();
        _loading = false;
        _hasMore = true;
      });
      _applyInitialScrollPosition();
      _scheduleInitialReadAndDelivered();
    }

    try {
      final list = await repo.syncMessages(chatId, limit: 50);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _reindexMessages();
        _initUnreadDividerAnchorOnce();
        _loading = false;
        _hasMore = true;
      });
      _applyInitialScrollPosition();
      _scheduleInitialReadAndDelivered();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initUnreadDividerAnchorOnce();
        _loading = false;
      });
    }

    await _ensureRealtime();
    await _refreshMyChatRole();
  }

  Future<void> _resyncAfterReconnect() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    try {
      final list = await _repo.syncMessages(chatId, limit: 200);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _reindexMessages();
      });
      _scheduleMarkRead();
      _scheduleMarkDelivered();
    } catch (_) {
      // ignore transient reconnect sync errors
    }
  }

  Future<void> _ensureRealtime() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    final repo = context.read<ChatsRepository>();

    _myUserId ??= await _readMyUserId();

    final peerId = widget.chat.peerId ?? 0;

    await _realtimeCoordinator.ensureConnected(
      chatId: chatId,
      isPrivateChat: _isPrivateChat,
      peerId: peerId,
      onEvent: (evt) => _handleRealtimeEvent(evt, chatId: chatId, repo: repo),
    );
  }

  Future<void> _handleRealtimeEvent(
    RealtimeEvent evt, {
    required int chatId,
    required ChatsRepository repo,
  }) async {
    switch (evt.type) {
      case 'error':
        _handleRealtimeErrorEvent(evt, chatId: chatId);
        return;
      case 'presence':
        _handlePresenceEvent(evt);
        return;
      case 'connection':
        _handleConnectionEvent(evt);
        return;
      case 'profile_updated':
        _handleProfileUpdatedEvent(evt);
        return;
      case 'member_added':
      case 'member_removed':
      case 'member_role_changed':
        _handleMemberEvent(evt, chatId: chatId);
        return;
      case 'message_delivered':
        _handleMessageDeliveredEvent(evt, chatId: chatId);
        return;
      case 'message_read':
        _handleMessageReadEvent(evt, chatId: chatId);
        return;
      case 'message_updated':
        await _handleMessageUpdatedEvent(evt, chatId: chatId, repo: repo);
        return;
      case 'message_deleted':
        _handleMessageDeletedEvent(evt, chatId: chatId);
        return;
      case 'typing':
        _handleTypingEvent(evt, chatId: chatId);
        return;
      case 'message_new':
        await _handleMessageNewEvent(evt, chatId: chatId, repo: repo);
        return;
      default:
        return;
    }
  }

  void _handleRealtimeErrorEvent(RealtimeEvent evt, {required int chatId}) {
    final evtChatId = _asInt(evt.data['chat_id'] ?? evt.data['chatId']);
    if (evtChatId > 0 && evtChatId != chatId) return;

    final raw = (evt.data['error'] ?? evt.data['message'] ?? '')
        .toString()
        .trim();
    final message = raw.isNotEmpty ? raw : 'Не удалось отправить сообщение';
    if (kDebugMode) {
      debugPrint('WS error event: $message');
    }
    if (!mounted) return;
    showGlassSnack(context, message, kind: GlassSnackKind.error);
  }

  void _handlePresenceEvent(RealtimeEvent evt) {
    if (!_isPrivateChat) return;
    final peerId = widget.chat.peerId ?? 0;
    final userId = evt.data['user_id'] ?? evt.data['userId'] ?? evt.data['id'];
    if ('$userId' != '$peerId') return;

    final statusRaw =
        (evt.data['status'] ??
                evt.data['state'] ??
                evt.data['online'] ??
                evt.data['is_online'] ??
                evt.data['isOnline'])
            .toString()
            .trim()
            .toLowerCase();
    final online =
        statusRaw == 'online' || statusRaw == 'true' || statusRaw == '1';
    if (online != _peerOnline && mounted) {
      setState(() {
        _peerOnline = online;
      });
    }
  }

  void _handleConnectionEvent(RealtimeEvent evt) {
    final reconnected = evt.data['reconnected'] == true;
    if (reconnected) {
      unawaited(_resyncAfterReconnect());
      unawaited(_refreshMyChatRole());
    }
  }

  void _handleProfileUpdatedEvent(RealtimeEvent evt) {
    if (!_isPrivateChat) return;
    final userDyn = evt.data['user'];
    if (userDyn is! Map) return;
    final u = (userDyn is Map<String, dynamic>)
        ? userDyn
        : Map<String, dynamic>.fromEntries(
            userDyn.entries.map((e) => MapEntry(e.key.toString(), e.value)),
          );
    final userId = (u['id'] is int)
        ? u['id'] as int
        : int.tryParse('${u['id'] ?? ''}') ?? 0;
    final peerId = widget.chat.peerId ?? 0;
    if (userId <= 0 || userId != peerId) return;

    final username = ((u['username'] as String?) ?? '').trim();
    final avatarRaw = ((u['avatar'] as String?) ?? '').trim();
    final avatar = avatarRaw.isEmpty ? '' : _avatarUrl(avatarRaw);
    if (!mounted) return;
    setState(() {
      if (username.isNotEmpty) {
        _peerName = username;
      }
      _peerAvatarUrl = avatar;
    });
  }

  void _handleMemberEvent(RealtimeEvent evt, {required int chatId}) {
    final evtChatId = _asInt(evt.data['chat_id'] ?? evt.data['chatId']);
    if (evtChatId != chatId) return;

    final targetUserId = _asInt(evt.data['user_id'] ?? evt.data['userId']);
    final myId = _myUserId ?? 0;
    if (evt.type == 'member_removed' &&
        myId > 0 &&
        targetUserId > 0 &&
        targetUserId == myId) {
      if (!mounted) return;
      showGlassSnack(
        context,
        'Вы были удалены из этого чата',
        kind: GlassSnackKind.info,
      );
      Navigator.of(context).maybePop();
      return;
    }

    unawaited(_refreshMyChatRole());
  }

  void _handleMessageDeliveredEvent(RealtimeEvent evt, {required int chatId}) {
    final evtChatId = _asInt(evt.data['chat_id'] ?? evt.data['chatId']);
    if (evtChatId != chatId) return;
    final userId = _asInt(evt.data['user_id'] ?? evt.data['userId']);
    final lastDelivered = _asInt(
      evt.data['last_delivered_message_id'] ??
          evt.data['lastDeliveredMessageId'],
    );
    final myId = _myUserId ?? 0;
    if (userId == myId && lastDelivered > _lastDeliveredMarkedMessageId) {
      _lastDeliveredMarkedMessageId = lastDelivered;
      return;
    }

    if (_isPrivateChat && userId != myId && lastDelivered > 0 && mounted) {
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final msg = _messages[i];
          if (!msg.isMe || msg.isDelivered) continue;
          final mid = int.tryParse(msg.id) ?? 0;
          if (mid <= 0 || mid > lastDelivered) continue;
          final updated = msg.copyWith(isDelivered: true);
          _messages[i] = updated;
          _messageById[msg.id] = updated;
        }
      });
    }
  }

  void _handleMessageReadEvent(RealtimeEvent evt, {required int chatId}) {
    final evtChatId = _asInt(evt.data['chat_id'] ?? evt.data['chatId']);
    if (evtChatId != chatId) return;
    final userId = _asInt(evt.data['user_id'] ?? evt.data['userId']);
    final lastRead = _asInt(
      evt.data['last_read_message_id'] ?? evt.data['lastReadMessageId'],
    );
    final myId = _myUserId ?? 0;
    if (userId == myId && lastRead > _lastReadMarkedMessageId) {
      _lastReadMarkedMessageId = lastRead;
      if (mounted) {
        setState(() {
          _clearUnreadDividerIfCoveredByReadCursor(lastRead);
        });
      } else {
        _clearUnreadDividerIfCoveredByReadCursor(lastRead);
      }
      return;
    }

    if (_isPrivateChat && userId != myId && lastRead > 0 && mounted) {
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final msg = _messages[i];
          if (!msg.isMe || msg.isRead) continue;
          final mid = int.tryParse(msg.id) ?? 0;
          if (mid <= 0 || mid > lastRead) continue;
          final updated = msg.copyWith(isDelivered: true, isRead: true);
          _messages[i] = updated;
          _messageById[msg.id] = updated;
        }
      });
    }
  }

  Future<void> _handleMessageUpdatedEvent(
    RealtimeEvent evt, {
    required int chatId,
    required ChatsRepository repo,
  }) async {
    final evtChatId = evt.data['chat_id'];
    if ('$evtChatId' != '$chatId') return;

    final msg = evt.data['message'];
    if (msg is! Map) return;

    final m = (msg is Map<String, dynamic>)
        ? msg
        : Map<String, dynamic>.fromEntries(
            msg.entries.map((e) => MapEntry(e.key.toString(), e.value)),
          );

    final decoded = await repo.decryptIncomingWsMessageFull(message: m);
    final incomingId = '${m['id'] ?? ''}';
    if (incomingId.isEmpty) return;

    if (!mounted) return;
    setState(() {
      var idx = -1;
      for (var i = _messages.length - 1; i >= 0; i--) {
        if (_messages[i].id == incomingId) {
          idx = i;
          break;
        }
      }
      if (idx < 0) return;
      final old = _messages[idx];
      final updated = old.copyWith(text: decoded.text);

      _messages[idx] = updated;
      _messageById[incomingId] = updated;

      if (_editing?.id == incomingId) {
        _editing = null;
      }
    });
  }

  void _handleMessageDeletedEvent(RealtimeEvent evt, {required int chatId}) {
    final evtChatId = evt.data['chat_id'];
    if ('$evtChatId' != '$chatId') return;

    final mid = evt.data['message_id'];
    final messageId = (mid is int) ? mid : int.tryParse('$mid') ?? 0;
    if (messageId <= 0) return;

    if (!mounted) return;
    setState(() {
      final idStr = messageId.toString();

      for (var i = _messages.length - 1; i >= 0; i--) {
        if (_messages[i].id == idStr) {
          _messages.removeAt(i);
        }
      }

      _messageById.remove(idStr);
      final nextSelected = Set<String>.from(_selectedMessageIdsN.value);
      nextSelected.removeWhere((id) => id == idStr);
      _selectedMessageIdsN.value = nextSelected;
      if (nextSelected.isEmpty) {
        _selectionModeN.value = false;
      }
      if (_replyTo?.id == idStr) {
        _replyTo = null;
      }
    });
  }

  void _handleTypingEvent(RealtimeEvent evt, {required int chatId}) {
    final peerId = widget.chat.peerId ?? 0;
    final evtChatId = evt.data['chat_id'];
    final userId = evt.data['user_id'];
    if ('$evtChatId' == '$chatId' && '$userId' == '$peerId') {
      final isTyping = evt.data['is_typing'] == true;
      if (isTyping != _peerTyping && mounted) {
        setState(() {
          _peerTyping = isTyping;
        });
      }
    }
  }

  Future<void> _handleMessageNewEvent(
    RealtimeEvent evt, {
    required int chatId,
    required ChatsRepository repo,
  }) async {
    final evtChatId = evt.data['chat_id'];
    if ('$evtChatId' != '$chatId') return;

    final msg = evt.data['message'];
    if (msg is! Map) return;

    final m = (msg is Map<String, dynamic>)
        ? msg
        : Map<String, dynamic>.fromEntries(
            msg.entries.map((e) => MapEntry(e.key.toString(), e.value)),
          );

    if (kDebugMode) {
      debugPrint('WS message_new payload keys: ${m.keys.toList()}');
    }

    final decoded = await repo.decryptIncomingWsMessageFull(message: m);

    final senderId = m['sender_id'] is int
        ? m['sender_id'] as int
        : int.tryParse('${m['sender_id']}') ?? 0;
    final createdAtStr = (m['created_at'] as String?) ?? '';
    final createdAt = (DateTime.tryParse(createdAtStr) ?? DateTime.now())
        .toLocal();

    final replyDyn = m['reply_to_message_id'] ?? m['replyToMessageId'];
    final replyId = (replyDyn is int)
        ? replyDyn
        : int.tryParse('${replyDyn ?? ''}');

    final myId = _myUserId ?? 0;
    final isMe = (myId > 0) ? senderId == myId : false;

    if (kDebugMode) {
      debugPrint('WS message_new routing resolved (isMe=$isMe)');
    }

    if (!mounted) return;
    setState(() {
      final incomingId = '${m['id'] ?? ''}';
      if (incomingId.isNotEmpty && _messageById.containsKey(incomingId)) {
        return;
      }

      // если это echo нашего сообщения, попробуем убрать последний optimistic дубль
      if (isMe && _messages.isNotEmpty) {
        final last = _messages.last;
        if (last.id.startsWith('local_') && last.text == decoded.text) {
          final removed = _messages.removeLast();
          _messageById.remove(removed.id);
        }
      }

      final created = ChatMessage(
        id: '${m['id'] ?? DateTime.now().millisecondsSinceEpoch}',
        chatId: chatId.toString(),
        isMe: isMe,
        text: decoded.text,
        attachments: decoded.attachments,
        sentAt: createdAt,
        replyToMessageId: (replyId != null && replyId > 0)
            ? replyId.toString()
            : null,
        isDelivered: m['is_delivered'] == true || m['isDelivered'] == true,
        isRead: m['is_read'] == true || m['isRead'] == true,
      );
      _messages.add(created);
      _messageById[created.id] = created;
    });

    if (isMe || _isAtBottom) {
      _scheduleScrollToBottom(animated: true);
    }
    if (!isMe) {
      if (!_isAtBottom) {
        setState(() {
          _newMessagesWhileAway += 1;
        });
        _jumpBadgePulse
          ..stop()
          ..forward(from: 0);
      }
      _scheduleMarkDelivered();
      _scheduleMarkRead();
    }
  }

  Future<int> _readMyUserId() async {
    final v = await SecureStorage.readKey(Keys.userId);
    return int.tryParse(v ?? '') ?? 0;
  }

  void _applyOptimisticEdit({
    required ChatMessage editing,
    required String text,
  }) {
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == editing.id);
      if (idx >= 0) {
        final old = _messages[idx];
        _messages[idx] = old.copyWith(text: text);
        _reindexMessages();
      }
    });
  }

  String _addOptimisticLocalMessage({
    required int chatId,
    required String text,
    required List<ChatAttachment> optimisticAttachments,
    required ChatMessage? replyTo,
  }) {
    final optimisticId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _messages.add(
        ChatMessage(
          id: optimisticId,
          chatId: chatId.toString(),
          isMe: true,
          text: text,
          attachments: optimisticAttachments,
          sentAt: DateTime.now(),
          replyToMessageId: replyTo?.id,
          isDelivered: false,
          isRead: false,
        ),
      );
      _reindexMessages();
    });
    return optimisticId;
  }

  Future<Map<String, dynamic>> _buildSendPayload({
    required bool hasAttachments,
    required ChatsRepository repo,
    required int chatId,
    required int peerId,
    required String text,
    required List<OutgoingAttachment> outgoingAttachments,
  }) async {
    if (hasAttachments) {
      return await repo.buildOutgoingWsMediaMessage(
        chatId: chatId,
        chatKind: widget.chat.kind,
        peerId: peerId > 0 ? peerId : null,
        caption: text,
        attachments: outgoingAttachments,
      );
    }
    return await repo.buildOutgoingWsTextMessage(
      chatId: chatId,
      chatKind: widget.chat.kind,
      peerId: peerId > 0 ? peerId : null,
      plaintext: text,
    );
  }

  String _resolveWsType(List<PendingChatAttachment> pendingToSend) {
    if (pendingToSend.isEmpty) return 'send_message';
    final hasAudio = pendingToSend.any(
      (p) => p.mimetype.toLowerCase().startsWith('audio/'),
    );
    final hasVideo = pendingToSend.any(
      (p) => p.mimetype.toLowerCase().startsWith('video/'),
    );
    if (hasAudio && !hasVideo) return 'voice_message';
    if (hasVideo && !hasAudio) return 'video_message';
    return 'send_message';
  }

  void _restoreDraftAfterSendError({
    required String? optimisticId,
    required Set<String> pendingIds,
    required Object error,
    required ChatMessage? replyTo,
    required ChatMessage? editing,
    required String draftText,
  }) {
    setState(() {
      if (optimisticId != null) {
        _messages.removeWhere((m) => m.id == optimisticId);
        _messageById.remove(optimisticId);
      }
      _pendingController.setStateByIds(
        pendingIds,
        PendingAttachmentState.failed,
        error: '$error',
      );
      _replyTo = replyTo;
      _editing = editing;
    });
    _controller.text = draftText;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    showGlassSnack(
      context,
      'Не удалось отправить сообщение. Черновик восстановлен.',
      kind: GlassSnackKind.error,
    );
    print(error);
    _scheduleScrollToBottom(animated: false);
  }

  Future<void> _send() async {
    if (!_canSendInCurrentChat) {
      showGlassSnack(
        context,
        'У вас нет прав на отправку сообщений в этом канале',
        kind: GlassSnackKind.info,
      );
      return;
    }
    if (_isSendingMessage) return;
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    final peerId = widget.chat.peerId ?? 0;
    if (chatId <= 0) {
      showGlassSnack(
        context,
        'Некорректный идентификатор чата. Перезайдите в чат.',
        kind: GlassSnackKind.error,
      );
      return;
    }
    final text = _controller.text.trim();
    final pendingToSend = _pendingController.queuedPendingAttachments();
    final pendingIds = pendingToSend.map((p) => p.clientId).toSet();
    final hasAttachments = pendingToSend.isNotEmpty;
    if (text.isEmpty && !hasAttachments) return;
    if (_isPrivateChat && peerId <= 0) {
      showGlassSnack(
        context,
        'Не удалось определить собеседника в этом чате.',
        kind: GlassSnackKind.error,
      );
      return;
    }

    final repo = context.read<ChatsRepository>();
    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;
    final draftText = text;

    _typingDebounce?.cancel();
    _sendTyping(false);

    final replyTo = _replyTo;
    final editing = _editing;
    String? optimisticId;
    setState(() {
      _isSendingMessage = true;
      _pendingController.setStateByIds(
        pendingIds,
        PendingAttachmentState.sending,
      );
      _replyTo = null;
      _editing = null;
    });
    _controller.clear();

    try {
      if (editing != null) {
        // редактирование: поддерживаем только текст без файлов
        if (hasAttachments || editing.attachments.isNotEmpty) {
          return;
        }

        _applyOptimisticEdit(editing: editing, text: text);

        final payload = await repo.buildOutgoingWsTextMessage(
          chatId: chatId,
          chatKind: widget.chat.kind,
          peerId: peerId > 0 ? peerId : null,
          plaintext: text,
        );

        if (!rt.isConnected) {
          await rt.connect();
        }
        rt.joinChat(chatId);

        final mid = int.tryParse(editing.id) ?? 0;
        if (mid > 0) {
          rt.editMessage(
            chatId: chatId,
            messageId: mid,
            message: payload['message'] as String,
            messageType: payload['message_type'] as String?,
            envelopes: payload['envelopes'] as Map<String, dynamic>?,
            metadata: payload['metadata'] as List<dynamic>?,
          );
        }
        return;
      }

      final optimisticAtt = await _attachmentsPreparer
          .buildOptimisticAttachments(pendingToSend);
      optimisticId = _addOptimisticLocalMessage(
        chatId: chatId,
        text: text,
        optimisticAttachments: optimisticAtt,
        replyTo: replyTo,
      );

      _scheduleScrollToBottom(animated: true);

      final outgoingAttachments = hasAttachments
          ? await _attachmentsPreparer.buildOutgoingAttachments(pendingToSend)
          : const <OutgoingAttachment>[];

      final payload = await _buildSendPayload(
        hasAttachments: hasAttachments,
        repo: repo,
        chatId: chatId,
        peerId: peerId,
        text: text,
        outgoingAttachments: outgoingAttachments,
      );

      final wsType = _resolveWsType(pendingToSend);

      if (!rt.isConnected) {
        await rt.connect();
      }
      rt.joinChat(chatId);

      rt.sendMessage(
        chatId: chatId,
        message: payload['message'] as String,
        wsType: wsType,
        messageType: payload['message_type'] as String?,
        envelopes: payload['envelopes'] as Map<String, dynamic>?,
        metadata: payload['metadata'] as List<dynamic>?,
        replyToMessageId: replyTo == null ? null : int.tryParse(replyTo.id),
      );
      if (!mounted) return;
      setState(() {
        _pendingController.removeByIds(pendingIds);
      });
    } catch (e) {
      if (!mounted) return;
      _restoreDraftAfterSendError(
        optimisticId: optimisticId,
        pendingIds: pendingIds,
        error: e,
        replyTo: replyTo,
        editing: editing,
        draftText: draftText,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
    }
  }

  Future<void> _sendRecordedVoice(PendingChatAttachment attachment) async {
    await _sendRecordedMedia(
      attachment: attachment,
      defaultFilenamePrefix: 'voice',
      defaultFilenameExtension: 'm4a',
      wsType: 'voice_message',
      sendErrorMessage: 'Не удалось отправить голосовое сообщение.',
    );
  }

  Future<void> _sendRecordedVideo(PendingChatAttachment attachment) async {
    await _sendRecordedMedia(
      attachment: attachment,
      defaultFilenamePrefix: 'video',
      defaultFilenameExtension: 'mp4',
      wsType: 'video_message',
      sendErrorMessage: 'Не удалось отправить видео.',
    );
  }

  Future<void> _sendRecordedMedia({
    required PendingChatAttachment attachment,
    required String defaultFilenamePrefix,
    required String defaultFilenameExtension,
    required String wsType,
    required String sendErrorMessage,
  }) async {
    if (!_canSendInCurrentChat) {
      showGlassSnack(
        context,
        'У вас нет прав на отправку сообщений в этом канале',
        kind: GlassSnackKind.info,
      );
      return;
    }
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    final peerId = widget.chat.peerId ?? 0;
    if (chatId <= 0) {
      showGlassSnack(
        context,
        'Некорректный идентификатор чата. Перезайдите в чат.',
        kind: GlassSnackKind.error,
      );
      return;
    }
    if (_isPrivateChat && peerId <= 0) {
      showGlassSnack(
        context,
        'Не удалось определить собеседника в этом чате.',
        kind: GlassSnackKind.error,
      );
      return;
    }
    if (!_canAttachFileSize(attachment.sizeBytes)) return;

    final repo = context.read<ChatsRepository>();

    final safeName = attachment.filename.isNotEmpty
        ? attachment.filename
        : '${defaultFilenamePrefix}_${DateTime.now().millisecondsSinceEpoch}.$defaultFilenameExtension';
    final preview = await _attachmentsPreparer.resolveOptimisticAttachment(
      attachment,
    );
    final path = preview.localPath;

    final replyTo = _replyTo;
    final optimisticId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    if (mounted) {
      setState(() {
        _replyTo = null;
        _messages.add(
          ChatMessage(
            id: optimisticId,
            chatId: chatId.toString(),
            isMe: true,
            text: '',
            attachments: [
              ChatAttachment(
                localPath: path,
                filename: safeName,
                mimetype: attachment.mimetype,
                size: attachment.sizeBytes,
              ),
            ],
            sentAt: DateTime.now(),
            replyToMessageId: replyTo?.id,
            isDelivered: false,
            isRead: false,
          ),
        );
        _reindexMessages();
      });
    }
    _scheduleScrollToBottom(animated: true);

    try {
      final payload = await repo.buildOutgoingWsMediaMessage(
        chatId: chatId,
        chatKind: widget.chat.kind,
        peerId: _isPrivateChat ? peerId : null,
        caption: '',
        attachments: [
          OutgoingAttachment(
            bytes: await _attachmentsPreparer.readPendingAttachmentBytes(
              attachment,
            ),
            filename: safeName,
            mimetype: attachment.mimetype,
          ),
        ],
      );

      await _ensureWsReady(chatId);
      final rt = _rt!;
      rt.sendMessage(
        chatId: chatId,
        message: payload['message'] as String,
        wsType: wsType,
        messageType: payload['message_type'] as String?,
        envelopes: payload['envelopes'] as Map<String, dynamic>?,
        metadata: payload['metadata'] as List<dynamic>?,
        replyToMessageId: replyTo == null ? null : int.tryParse(replyTo.id),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == optimisticId);
        _messageById.remove(optimisticId);
        _replyTo = replyTo;
      });
      showGlassSnack(context, sendErrorMessage, kind: GlassSnackKind.error);
    }
  }

  Future<void> _pickPhotos() async {
    final added = await _attachmentsPickerController.pickPhotos(
      newClientId: _pendingController.newPendingId,
      canAttachFileSize: _canAttachFileSize,
    );
    if (added.isEmpty || !mounted) return;
    setState(() {
      _pendingController.addAll(added);
    });
  }

  Future<void> _takePhoto() async {
    final attachment = await _attachmentsPickerController.takePhoto(
      newClientId: _pendingController.newPendingId,
      canAttachFileSize: _canAttachFileSize,
    );
    if (attachment == null || !mounted) return;
    setState(() {
      _pendingController.add(attachment);
    });
  }

  Future<void> _pickFiles() async {
    final added = await _attachmentsPickerController.pickFiles(
      newClientId: _pendingController.newPendingId,
      canAttachFileSize: _canAttachFileSize,
    );
    if (added.isEmpty || !mounted) return;
    setState(() {
      _pendingController.addAll(added);
    });
  }

  void _cancelEditing() {
    if (_editing == null) return;
    setState(() {
      _editing = null;
    });
    _controller.clear();
  }

  void _cancelReply() {
    if (_replyTo == null) return;
    setState(() {
      _replyTo = null;
    });
  }

  void _removePendingAt(int index) {
    if (!_pendingController.canRemoveAt(index)) return;
    setState(() {
      _pendingController.removeAt(index);
    });
  }

  void _retryPendingAt(int index) {
    if (!_pendingController.canRetryAt(index)) return;
    setState(() {
      _pendingController.retryAt(index);
    });
  }

  void _onRecorderChanged(RecorderMode mode, bool isRecording) {
    if (mode != RecorderMode.video) return;
    _setVideoRecordingOverlay(show: isRecording);
  }

  void _onRecorderLockedChanged(RecorderMode mode, bool locked) {
    if (mode != RecorderMode.video) return;
    _onVideoRecordingLockedChanged(locked);
  }

  void _onRecorderControllerChanged(VoidCallback cancel, VoidCallback stop) {
    _cancelVideoRecording = cancel;
    _stopVideoRecording = stop;
  }

  void _onVideoActionsControllerChanged(
    Future<bool> Function(bool enabled) setTorch,
    Future<bool> Function(bool useFront) setUseFrontCamera,
  ) {
    _setVideoTorch = setTorch;
    _setVideoUseFrontCamera = setUseFrontCamera;
  }

  Future<void> _handleAddRecordedFile(PendingChatAttachment attachment) async {
    if (!mounted) return;
    if ((attachment.mimetype).toLowerCase().startsWith('audio/')) {
      await _sendRecordedVoice(attachment);
      return;
    }
    if ((attachment.mimetype).toLowerCase().startsWith('video/')) {
      await _sendRecordedVideo(attachment);
      return;
    }
    if (!_canAttachFileSize(attachment.sizeBytes)) return;
    setState(() {
      _pendingController.add(attachment.markQueued());
    });
  }

  void _cancelVideoOverlayRecording() {
    _cancelVideoRecording?.call();
  }

  Future<void> _toggleVideoFlash() async {
    if (!mounted) return;
    final next = !_videoFlashEnabled;
    setState(() {
      _videoFlashEnabled = next;
    });
    final ok = await _setVideoTorch?.call(next);
    if (ok != true && mounted) {
      setState(() {
        _videoFlashEnabled = !next;
      });
    }
  }

  Future<void> _toggleVideoUseFrontCamera() async {
    if (!mounted) return;
    final next = !_videoUseFrontCamera;
    setState(() {
      _videoUseFrontCamera = next;
    });
    final ok = await _setVideoUseFrontCamera?.call(next);
    if (ok != true && mounted) {
      setState(() {
        _videoUseFrontCamera = !next;
      });
    }
  }

  void _stopVideoOverlayRecording() {
    _stopVideoRecording?.call();
  }

  void _onAppBarBackPressed() {
    if (_selectionModeN.value) {
      _exitSelectionMode();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _onAppBarShareSelected() {
    unawaited(_forwardSelected());
  }

  void _onAppBarDeleteSelected(Set<String> selectedIds) {
    final ids = Set<String>.from(selectedIds);
    _deleteByIds(ids);
    _deleteRemote(ids);
  }

  @override
  void dispose() {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (_scrollController.hasClients) {
      final offset = _scrollController.offset;
      _savedScrollOffsetByChatId[widget.chat.id] = offset;
      unawaited(_repo.saveChatScrollOffset(widget.chat.id, offset));
    }
    final snapshot = List<ChatMessage>.from(_messages);
    unawaited(_repo.saveMessagesSnapshot(chatId, snapshot));
    WidgetsBinding.instance.removeObserver(this);
    _videoProgressController.dispose();
    _videoLockedTransition.dispose();
    _videoPulse.dispose();
    _jumpBadgePulse.dispose();
    _pressedMessageIdN.dispose();
    _selectionModeN.dispose();
    _selectedMessageIdsN.dispose();
    _typingDebounce?.cancel();
    _typingDebounce = null;
    _markReadDebounce?.cancel();
    _markReadDebounce = null;
    _markDeliveredDebounce?.cancel();
    _markDeliveredDebounce = null;
    _loadOlderDebounce?.cancel();
    _loadOlderDebounce = null;
    _rt?.typing(chatId, false);
    _rt?.leaveChat(chatId);
    unawaited(_realtimeCoordinator.dispose());
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _scrollController.removeListener(_onScroll);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildUnreadDivider(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.primary.withOpacity(0.30),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Новые сообщения',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary.withOpacity(0.92),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.primary.withOpacity(0.30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesPane({
    required ThemeData theme,
    required bool isDark,
    required bool selectionMode,
    required Set<String> selectedIds,
    required double listTopPadding,
    required double listBottomPadding,
  }) {
    const double horizontalPadding = 14;
    return Positioned.fill(
      child: _loading
          ? ListView.separated(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                listTopPadding,
                horizontalPadding,
                listBottomPadding,
              ),
              itemCount: 10,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final alignRight = index.isOdd;
                return Align(
                  alignment: alignRight
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: ChatSkeletonMessageBubble(isMe: alignRight),
                );
              },
            )
          : ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                listTopPadding,
                horizontalPadding,
                listBottomPadding,
              ),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final replyToId = msg.replyToMessageId;
                final replied = (replyToId == null || replyToId.isEmpty)
                    ? null
                    : _findMessageById(replyToId);
                final replyPreview = (replied == null)
                    ? null
                    : _messageSummary(replied);
                final selected = selectionMode && selectedIds.contains(msg.id);
                final showUnreadDivider = _firstUnreadMessageId == msg.id;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showUnreadDivider) _buildUnreadDivider(theme),
                    Align(
                      alignment: msg.isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Dismissible(
                        key: ValueKey('reply_${msg.id}'),
                        direction: selectionMode
                            ? DismissDirection.none
                            : (msg.isMe
                                  ? DismissDirection.endToStart
                                  : DismissDirection.startToEnd),
                        movementDuration: const Duration(milliseconds: 260),
                        dismissThresholds: {
                          DismissDirection.startToEnd: 0.22,
                          DismissDirection.endToStart: 0.22,
                        },
                        confirmDismiss: (_) async {
                          if (selectionMode) return false;
                          HapticFeedback.selectionClick();
                          if (!mounted) return false;
                          setState(() {
                            _replyTo = msg;
                            _editing = null;
                          });
                          _focusNode.requestFocus();
                          return false;
                        },
                        background: Align(
                          alignment: msg.isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.reply,
                              size: 18,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.55,
                              ),
                            ),
                          ),
                        ),
                        secondaryBackground: Align(
                          alignment: msg.isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.reply,
                              size: 18,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.55,
                              ),
                            ),
                          ),
                        ),
                        child: Container(
                          key: _messageKey(msg.id),
                          child: GestureDetector(
                            onTapDown: (_) {
                              if (!mounted) return;
                              if (_pressedMessageIdN.value == msg.id) {
                                return;
                              }
                              _pressedMessageIdN.value = msg.id;
                            },
                            onTapCancel: () {
                              if (!mounted) return;
                              if (_pressedMessageIdN.value != msg.id) {
                                return;
                              }
                              _pressedMessageIdN.value = null;
                            },
                            onTapUp: (_) {
                              if (!mounted) return;
                              if (_pressedMessageIdN.value != msg.id) {
                                return;
                              }
                              _pressedMessageIdN.value = null;
                            },
                            onTap: () {
                              if (selectionMode) {
                                _toggleSelected(msg);
                              }
                            },
                            onLongPressStart: (d) async {
                              HapticFeedback.selectionClick();
                              if (mounted &&
                                  _pressedMessageIdN.value != msg.id) {
                                _pressedMessageIdN.value = msg.id;
                              }
                              if (selectionMode) {
                                _toggleSelected(msg);
                              } else {
                                await _showMessageContextMenu(
                                  msg,
                                  d.globalPosition,
                                );
                              }

                              if (mounted &&
                                  _pressedMessageIdN.value == msg.id) {
                                _pressedMessageIdN.value = null;
                              }
                            },
                            onLongPressEnd: (_) {
                              if (!mounted) return;
                              if (_pressedMessageIdN.value != msg.id) {
                                return;
                              }
                              _pressedMessageIdN.value = null;
                            },
                            child: ValueListenableBuilder<String?>(
                              valueListenable: _pressedMessageIdN,
                              builder: (context, pressedId, child) {
                                final pressed = pressedId == msg.id;
                                return AnimatedScale(
                                  scale: pressed
                                      ? 0.985
                                      : (selected ? 1.05 : 1.0),
                                  duration: const Duration(milliseconds: 110),
                                  curve: Curves.easeOut,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 110,
                                        ),
                                        curve: Curves.easeOut,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          color: pressed
                                              ? theme.colorScheme.onSurface
                                                    .withOpacity(
                                                      isDark ? 0.10 : 0.06,
                                                    )
                                              : (selected
                                                    ? theme.colorScheme.primary
                                                          .withOpacity(
                                                            isDark
                                                                ? 0.12
                                                                : 0.10,
                                                          )
                                                    : Colors.transparent),
                                          border: selected
                                              ? Border.all(
                                                  color: theme
                                                      .colorScheme
                                                      .primary
                                                      .withOpacity(0.8),
                                                  width: 1.2,
                                                )
                                              : null,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(2),
                                          child: RepaintBoundary(
                                            child: _buildMessageBubble(
                                              msg: msg,
                                              replyPreview: replyPreview,
                                              isDark: isDark,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: -6,
                                        top: -6,
                                        child: AnimatedOpacity(
                                          opacity: selected ? 1 : 0,
                                          duration: const Duration(
                                            milliseconds: 120,
                                          ),
                                          curve: Curves.easeOut,
                                          child: AnimatedScale(
                                            scale: selected ? 1 : 0.9,
                                            duration: const Duration(
                                              milliseconds: 120,
                                            ),
                                            curve: Curves.easeOut,
                                            child: Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color:
                                                    theme.colorScheme.primary,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: theme
                                                      .colorScheme
                                                      .surface
                                                      .withOpacity(0.9),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.check,
                                                size: 14,
                                                color:
                                                    theme.colorScheme.onPrimary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (index != _messages.length - 1)
                      const SizedBox(height: 10),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildInputPane({
    required MediaQueryData media,
    required bool isDark,
    required String replyText,
  }) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: _canSendInCurrentChat
              ? ChatInputBar(
                  controller: _controller,
                  focusNode: _focusNode,
                  isDark: isDark,
                  isEditing: _editing != null,
                  onCancelEditing: _cancelEditing,
                  hasReply: _replyTo != null,
                  replyText: replyText,
                  onCancelReply: _cancelReply,
                  pending: _pendingController.pending,
                  onRemovePending: _removePendingAt,
                  onRetryPending: _retryPendingAt,
                  onPickPhotos: _pickPhotos,
                  onPickFiles: _pickFiles,
                  onTakePhoto: _takePhoto,
                  onSend: _send,
                  onRecordingChanged: _onRecorderChanged,
                  onRecordingDurationChanged: _onVideoRecordingDurationChanged,
                  onRecordingLockedChanged: _onRecorderLockedChanged,
                  onRecorderController: _onRecorderControllerChanged,
                  onVideoControllerChanged: _onVideoControllerChanged,
                  onVideoActionsController: _onVideoActionsControllerChanged,
                  onAddRecordedFile: _handleAddRecordedFile,
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildJumpToBottomButton({
    required MediaQueryData media,
    required ThemeData theme,
  }) {
    final show = !_isAtBottom && media.viewInsets.bottom <= 0;
    const double inputHeight = 44;
    const double verticalPadding = 14;
    final bottomOffset =
        media.padding.bottom +
        media.viewInsets.bottom +
        inputHeight +
        verticalPadding +
        10;

    return Positioned(
      right: 14,
      bottom: bottomOffset,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        offset: show ? Offset.zero : const Offset(0, 0.35),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: show ? 1 : 0,
          child: IgnorePointer(
            ignoring: !show,
            child: GestureDetector(
              onTap: () {
                _scheduleScrollToBottom(animated: true);
                _scheduleMarkDelivered();
                _scheduleMarkRead();
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GlassSurface(
                    borderRadius: 999,
                    blurSigma: 12,
                    padding: const EdgeInsets.all(10),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowDown01,
                      size: 22,
                      color: theme.colorScheme.onSurface.withOpacity(0.88),
                    ),
                  ),
                  if (_newMessagesWhileAway > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: AnimatedBuilder(
                        animation: _jumpBadgePulse,
                        builder: (context, child) {
                          final t = Curves.easeOutBack.transform(
                            _jumpBadgePulse.value,
                          );
                          final scale = 1 + (0.16 * (1 - (t - 1).abs()));
                          return Transform.scale(
                            scale: scale.clamp(1.0, 1.16),
                            child: child,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.96),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          constraints: const BoxConstraints(minWidth: 18),
                          alignment: Alignment.center,
                          child: Text(
                            _newMessagesWhileAway > 99
                                ? '99+'
                                : '$_newMessagesWhileAway',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppBackground(
      imageOpacity: 1,
      imageBlurSigma: 0,
      imageFit: BoxFit.cover,
      animate: true,
      animationDuration: const Duration(seconds: 20),
      child: AnimatedBuilder(
        animation: _selectionListenable,
        builder: (context, child) {
          final selectionMode = _selectionModeN.value;
          final selectedIds = _selectedMessageIdsN.value;
          return ValueListenableBuilder<bool>(
            valueListenable: _messagesSyncingN,
            builder: (context, isSyncing, _) {
              return Scaffold(
                resizeToAvoidBottomInset: false,
                extendBodyBehindAppBar: true,
                appBar: ChatPageAppBar(
                  peerName: _peerName,
                  peerAvatarUrl: _peerAvatarUrl,
                  selectionMode: selectionMode,
                  selectedCount: selectedIds.length,
                  peerOnline: _peerOnline,
                  peerTyping: _peerTyping,
                  isSyncing: isSyncing,
                  chatKind: widget.chat.kind,
                  myRole: _myRoleInChat,
                  canSend: _canSendInCurrentChat,
                  onBack: _onAppBarBackPressed,
                  onShareSelected: _onAppBarShareSelected,
                  onDeleteSelected: () => _onAppBarDeleteSelected(selectedIds),
                  onMenu: _openMembersSheet,
                ),
                body: Builder(
                  builder: (context) {
                    final media = MediaQuery.of(context);
                    const double inputHeight = 44;
                    const double verticalPadding = 14;

                    final double topInset = media.padding.top;
                    // viewInsets.bottom is already applied via AnimatedPadding below.
                    final double bottomInset = media.padding.bottom;

                    final double listTopPadding =
                        topInset + kToolbarHeight + 12;
                    final double listBottomPadding =
                        bottomInset +
                        media.viewInsets.bottom +
                        inputHeight +
                        verticalPadding +
                        12;
                    final overlayBaseSize = math.min(
                      media.size.width,
                      media.size.height,
                    );
                    final videoOverlaySize = overlayBaseSize
                        .clamp(220.0, 320.0)
                        .toDouble();
                    final videoOverlayRadius = (videoOverlaySize * 0.10)
                        .clamp(24.0, 32.0)
                        .toDouble();
                    final videoCapsuleWidth = math.min(
                      320.0,
                      math.max(220.0, media.size.width - 24),
                    );

                    final replyText = _replyTo == null
                        ? ''
                        : _messageSummary(_replyTo!);

                    return Stack(
                      children: [
                        _buildMessagesPane(
                          theme: theme,
                          isDark: isDark,
                          selectionMode: selectionMode,
                          selectedIds: selectedIds,
                          listTopPadding: listTopPadding,
                          listBottomPadding: listBottomPadding,
                        ),
                        _buildInputPane(
                          media: media,
                          isDark: isDark,
                          replyText: replyText,
                        ),
                        _buildJumpToBottomButton(media: media, theme: theme),

                        if (_showVideoRecordingOverlay)
                          Positioned.fill(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: IgnorePointer(
                                    ignoring: !_videoRecordingLocked,
                                    child: AnimatedBuilder(
                                      animation: _videoLockedTransition,
                                      builder: (context, _) {
                                        final t = Curves.easeOut.transform(
                                          _videoLockedTransition.value,
                                        );
                                        if (t <= 0) return const SizedBox();
                                        return ClipRect(
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(
                                              sigmaX: 14 * t,
                                              sigmaY: 14 * t,
                                            ),
                                            child: Container(
                                              color: Colors.black.withOpacity(
                                                (isDark ? 0.25 : 0.10) * t,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedBuilder(
                                        animation: _videoLockedTransition,
                                        builder: (context, _) {
                                          final t = Curves.easeOutBack
                                              .transform(
                                                _videoLockedTransition.value,
                                              );
                                          final pulse = _videoPulse.value;
                                          final breathe = math.sin(
                                            pulse * math.pi * 2,
                                          );
                                          final breathingScale =
                                              1 + 0.006 * breathe;
                                          final scale =
                                              (1 - 0.02 * t) * breathingScale;
                                          final dy = -8.0 * t;
                                          return Transform.translate(
                                            offset: Offset(0, dy),
                                            child: Transform.scale(
                                              scale: scale,
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      videoOverlayRadius,
                                                    ),
                                                child: Container(
                                                  width: videoOverlaySize,
                                                  height: videoOverlaySize,
                                                  color: theme
                                                      .colorScheme
                                                      .surface
                                                      .withOpacity(
                                                        isDark ? 0.55 : 0.80,
                                                      ),
                                                  child: Stack(
                                                    children: [
                                                      if (_videoCameraController !=
                                                              null &&
                                                          _videoCameraController!
                                                              .value
                                                              .isInitialized)
                                                        Positioned.fill(
                                                          child: ClipRRect(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  videoOverlayRadius,
                                                                ),
                                                            child: FittedBox(
                                                              fit: BoxFit.cover,
                                                              child: SizedBox(
                                                                width:
                                                                    _videoCameraController!
                                                                        .value
                                                                        .previewSize
                                                                        ?.height ??
                                                                    videoOverlaySize,
                                                                height:
                                                                    _videoCameraController!
                                                                        .value
                                                                        .previewSize
                                                                        ?.width ??
                                                                    videoOverlaySize,
                                                                child: CameraPreview(
                                                                  _videoCameraController!,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                      else
                                                        Center(
                                                          child: HugeIcon(
                                                            icon: HugeIcons
                                                                .strokeRoundedVideo01,
                                                            size:
                                                                (videoOverlaySize *
                                                                        0.29)
                                                                    .clamp(
                                                                      68.0,
                                                                      92.0,
                                                                    ),
                                                            color: theme
                                                                .colorScheme
                                                                .onSurface
                                                                .withOpacity(
                                                                  0.85,
                                                                ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 14),
                                      AnimatedBuilder(
                                        animation: _videoLockedTransition,
                                        builder: (context, _) {
                                          final t = Curves.easeOut.transform(
                                            _videoLockedTransition.value,
                                          );
                                          final capsuleScale = 1 + 0.01 * t;
                                          final capsuleDy = -4.0 * t;
                                          return Transform.translate(
                                            offset: Offset(0, capsuleDy),
                                            child: Transform.scale(
                                              scale: capsuleScale,
                                              child: GlassSurface(
                                                borderRadius: 999,
                                                blurSigma: 12,
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      12,
                                                      10,
                                                      12,
                                                      10,
                                                    ),
                                                child: SizedBox(
                                                  width: videoCapsuleWidth,
                                                  child: Row(
                                                    children: [
                                                      AnimatedSwitcher(
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 220,
                                                            ),
                                                        switchInCurve:
                                                            Curves.easeOut,
                                                        switchOutCurve:
                                                            Curves.easeOut,
                                                        transitionBuilder: (child, anim) {
                                                          final curved =
                                                              CurvedAnimation(
                                                                parent: anim,
                                                                curve: Curves
                                                                    .easeOut,
                                                              );
                                                          return FadeTransition(
                                                            opacity: curved,
                                                            child: ScaleTransition(
                                                              scale:
                                                                  Tween<double>(
                                                                    begin: 0.92,
                                                                    end: 1.0,
                                                                  ).animate(
                                                                    curved,
                                                                  ),
                                                              child: SlideTransition(
                                                                position: Tween<Offset>(
                                                                  begin:
                                                                      const Offset(
                                                                        -0.10,
                                                                        0,
                                                                      ),
                                                                  end: Offset
                                                                      .zero,
                                                                ).animate(curved),
                                                                child: child,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        child:
                                                            _videoRecordingLocked
                                                            ? Row(
                                                                key: const ValueKey(
                                                                  'locked_cancel',
                                                                ),
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  GestureDetector(
                                                                    onTap:
                                                                        _cancelVideoOverlayRecording,
                                                                    child: GlassSurface(
                                                                      borderRadius:
                                                                          12,
                                                                      blurSigma:
                                                                          12,
                                                                      width: 32,
                                                                      height:
                                                                          32,
                                                                      child: Center(
                                                                        child: HugeIcon(
                                                                          icon:
                                                                              HugeIcons.strokeRoundedCancel01,
                                                                          size:
                                                                              20,
                                                                          color: theme
                                                                              .colorScheme
                                                                              .onSurface
                                                                              .withOpacity(
                                                                                0.9,
                                                                              ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 10,
                                                                  ),
                                                                ],
                                                              )
                                                            : const SizedBox(
                                                                key: ValueKey(
                                                                  'hold_cancel_spacer',
                                                                ),
                                                              ),
                                                      ),
                                                      AnimatedBuilder(
                                                        animation: _videoPulse,
                                                        builder: (context, _) {
                                                          final p = Curves
                                                              .easeInOut
                                                              .transform(
                                                                _videoPulse
                                                                    .value,
                                                              );
                                                          final s =
                                                              1.0 + 0.18 * p;
                                                          final o =
                                                              0.55 +
                                                              0.45 * (1 - p);
                                                          return Transform.scale(
                                                            scale: s,
                                                            child: Container(
                                                              width: 8,
                                                              height: 8,
                                                              decoration: BoxDecoration(
                                                                color: theme
                                                                    .colorScheme
                                                                    .error
                                                                    .withOpacity(
                                                                      o,
                                                                    ),
                                                                shape: BoxShape
                                                                    .circle,
                                                                boxShadow: [
                                                                  BoxShadow(
                                                                    color: theme
                                                                        .colorScheme
                                                                        .error
                                                                        .withOpacity(
                                                                          0.35 *
                                                                              o,
                                                                        ),
                                                                    blurRadius:
                                                                        10 +
                                                                        10 * p,
                                                                    spreadRadius:
                                                                        0.5 +
                                                                        0.8 * p,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        _videoRecordingDurationText,
                                                        style: theme
                                                            .textTheme
                                                            .titleSmall
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: theme
                                                                  .colorScheme
                                                                  .onSurface,
                                                            ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: AnimatedBuilder(
                                                          animation:
                                                              _videoProgressController,
                                                          builder: (context, _) {
                                                            return ClipRRect(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    999,
                                                                  ),
                                                              child: Container(
                                                                height: 4,
                                                                color: theme
                                                                    .colorScheme
                                                                    .onSurface
                                                                    .withOpacity(
                                                                      isDark
                                                                          ? 0.18
                                                                          : 0.12,
                                                                    ),
                                                                alignment: Alignment
                                                                    .centerLeft,
                                                                child: FractionallySizedBox(
                                                                  widthFactor:
                                                                      _videoProgressController
                                                                          .value
                                                                          .clamp(
                                                                            0.0,
                                                                            1.0,
                                                                          ),
                                                                  child: Container(
                                                                    color: theme
                                                                        .colorScheme
                                                                        .primary,
                                                                  ),
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                      AnimatedSwitcher(
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 220,
                                                            ),
                                                        switchInCurve:
                                                            Curves.easeOut,
                                                        switchOutCurve:
                                                            Curves.easeOut,
                                                        transitionBuilder: (child, anim) {
                                                          final curved =
                                                              CurvedAnimation(
                                                                parent: anim,
                                                                curve: Curves
                                                                    .easeOut,
                                                              );
                                                          return FadeTransition(
                                                            opacity: curved,
                                                            child: ScaleTransition(
                                                              scale:
                                                                  Tween<double>(
                                                                    begin: 0.92,
                                                                    end: 1.0,
                                                                  ).animate(
                                                                    curved,
                                                                  ),
                                                              child: SlideTransition(
                                                                position: Tween<Offset>(
                                                                  begin:
                                                                      const Offset(
                                                                        0.12,
                                                                        0,
                                                                      ),
                                                                  end: Offset
                                                                      .zero,
                                                                ).animate(curved),
                                                                child: child,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        child:
                                                            _videoRecordingLocked
                                                            ? Row(
                                                                key: const ValueKey(
                                                                  'locked_actions',
                                                                ),
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  const SizedBox(
                                                                    width: 10,
                                                                  ),
                                                                  GestureDetector(
                                                                    onTap:
                                                                        _toggleVideoFlash,
                                                                    child: GlassSurface(
                                                                      borderRadius:
                                                                          12,
                                                                      blurSigma:
                                                                          12,
                                                                      width: 32,
                                                                      height:
                                                                          32,
                                                                      child: Center(
                                                                        child: HugeIcon(
                                                                          icon:
                                                                              _videoFlashEnabled
                                                                              ? HugeIcons.strokeRoundedFlash
                                                                              : HugeIcons.strokeRoundedFlashOff,
                                                                          size:
                                                                              20,
                                                                          color: theme
                                                                              .colorScheme
                                                                              .onSurface
                                                                              .withOpacity(
                                                                                0.9,
                                                                              ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  GestureDetector(
                                                                    onTap:
                                                                        _toggleVideoUseFrontCamera,
                                                                    child: GlassSurface(
                                                                      borderRadius:
                                                                          12,
                                                                      blurSigma:
                                                                          12,
                                                                      width: 32,
                                                                      height:
                                                                          32,
                                                                      child: Center(
                                                                        child: HugeIcon(
                                                                          icon:
                                                                              HugeIcons.strokeRoundedExchange01,
                                                                          size:
                                                                              20,
                                                                          color: theme
                                                                              .colorScheme
                                                                              .onSurface
                                                                              .withOpacity(
                                                                                0.9,
                                                                              ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  GestureDetector(
                                                                    onTap:
                                                                        _stopVideoOverlayRecording,
                                                                    child: GlassSurface(
                                                                      borderRadius:
                                                                          12,
                                                                      blurSigma:
                                                                          12,
                                                                      width: 32,
                                                                      height:
                                                                          32,
                                                                      child: Center(
                                                                        child: HugeIcon(
                                                                          icon:
                                                                              HugeIcons.strokeRoundedSent,
                                                                          size:
                                                                              20,
                                                                          color: theme
                                                                              .colorScheme
                                                                              .onSurface
                                                                              .withOpacity(
                                                                                0.9,
                                                                              ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              )
                                                            : const SizedBox(
                                                                key: ValueKey(
                                                                  'hold_actions_spacer',
                                                                ),
                                                              ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _enterSelectionMode({ChatMessage? initial}) {
    if (!mounted) return;
    _selectionModeN.value = true;
    if (initial != null) {
      final next = Set<String>.from(_selectedMessageIdsN.value);
      next.add(initial.id);
      _selectedMessageIdsN.value = next;
    }
  }

  void _exitSelectionMode() {
    if (!mounted) return;
    _selectionModeN.value = false;
    if (_selectedMessageIdsN.value.isNotEmpty) {
      _selectedMessageIdsN.value = <String>{};
    }
  }

  void _toggleSelected(ChatMessage msg) {
    if (!mounted) return;
    final next = Set<String>.from(_selectedMessageIdsN.value);
    if (next.contains(msg.id)) {
      next.remove(msg.id);
    } else {
      next.add(msg.id);
    }
    _selectedMessageIdsN.value = next;
    if (next.isEmpty) {
      _selectionModeN.value = false;
    }
  }

  void _deleteByIds(Set<String> ids) {
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((m) => ids.contains(m.id));
      final nextSelected = Set<String>.from(_selectedMessageIdsN.value);
      nextSelected.removeWhere((id) => !_messages.any((m) => m.id == id));
      _selectedMessageIdsN.value = nextSelected;
      if (nextSelected.isEmpty) {
        _selectionModeN.value = false;
      }
      if (_replyTo != null && ids.contains(_replyTo!.id)) {
        _replyTo = null;
      }
    });
  }

  void _deleteRemote(Set<String> ids) {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;
    () async {
      await _ensureWsReady(chatId);
      final rt = _rt!;
      for (final id in ids) {
        final mid = int.tryParse(id);
        if (mid == null || mid <= 0) continue;
        rt.deleteMessage(chatId: chatId, messageId: mid);
      }
    }();
  }

  Future<void> _forwardSelected() async {
    if (!mounted) return;
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    final repo = context.read<ChatsRepository>();

    await _ensureWsReady(chatId);

    final chats = await repo.fetchChats();
    if (!mounted) return;

    final selectedChat = await showForwardTargetChatPicker(
      context: context,
      chats: chats,
    );

    if (!mounted) return;
    if (selectedChat == null) return;

    final toChatId = int.tryParse(selectedChat.id) ?? 0;
    final toPeerId = selectedChat.peerId ?? 0;
    if (toChatId <= 0) {
      return;
    }

    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;

    final ids = List<String>.from(_selectedMessageIdsN.value);
    ids.sort((a, b) => a.compareTo(b));

    for (final id in ids) {
      final mid = int.tryParse(id);
      if (mid == null || mid <= 0) continue;
      final msg = _messages
          .where((m) => m.id == id)
          .cast<ChatMessage?>()
          .firstWhere((m) => m != null, orElse: () => null);
      if (msg == null) continue;
      if (msg.attachments.isNotEmpty) continue;
      final payload = await repo.buildOutgoingWsTextMessage(
        chatId: toChatId,
        chatKind: selectedChat.kind,
        peerId: toPeerId > 0 ? toPeerId : null,
        plaintext: msg.text,
      );
      rt.forwardMessage(
        fromChatId: chatId,
        messageId: mid,
        toChatId: toChatId,
        message: payload['message'] as String,
        messageType: payload['message_type'] as String?,
        envelopes: payload['envelopes'] as Map<String, dynamic>?,
        metadata: payload['metadata'] as List<dynamic>?,
      );
    }

    _exitSelectionMode();
  }

  Future<void> _showMessageContextMenu(
    ChatMessage msg,
    Offset globalPosition,
  ) async {
    Future<void> doCopy() async {
      final t = msg.text.trim();
      if (t.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: t));
      if (!mounted) return;
      showGlassSnack(context, 'Скопировано', kind: GlassSnackKind.success);
    }

    Future<void> doForward() async {
      _enterSelectionMode(initial: msg);
      await _forwardSelected();
    }

    void doEdit() {
      setState(() {
        _editing = msg;
        _replyTo = null;
      });
      _controller.text = msg.text;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _focusNode.requestFocus();
    }

    final selected = await showChatMessageContextMenu(
      context: context,
      globalPosition: globalPosition,
      canEdit: msg.isMe && msg.attachments.isEmpty,
      hasAttachments: msg.attachments.isNotEmpty,
    );

    if (!mounted) return;
    switch (selected) {
      case ChatMessageMenuAction.reply:
        setState(() {
          _replyTo = msg;
        });
        _focusNode.requestFocus();
        break;
      case ChatMessageMenuAction.edit:
        doEdit();
        break;
      case ChatMessageMenuAction.copy:
        await doCopy();
        break;
      case ChatMessageMenuAction.share:
        await doForward();
        break;
      case ChatMessageMenuAction.select:
        _enterSelectionMode(initial: msg);
        break;
      case ChatMessageMenuAction.delete:
        _deleteByIds({msg.id});
        _deleteRemote({msg.id});
        break;
      default:
        break;
    }
  }
}
