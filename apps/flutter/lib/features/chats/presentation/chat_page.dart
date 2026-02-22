import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:mime/mime.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/shared/widgets/background.dart';
import 'package:ren/shared/widgets/avatar.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';
import 'package:ren/shared/widgets/context_menu.dart';
import 'package:path_provider/path_provider.dart';

import 'package:ren/features/chats/presentation/widgets/chat_attachment_viewer_sheet.dart';
import 'package:ren/features/chats/presentation/widgets/chat_input_bar.dart';
import 'package:ren/features/chats/presentation/widgets/chat_message_bubble.dart';
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

  final _picker = ImagePicker();

  final List<PendingChatAttachment> _pending = [];
  int _pendingIdCounter = 0;
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
  StreamSubscription? _rtSub;

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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const kb = 1024;
    const mb = 1024 * 1024;
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  String _newPendingId() {
    _pendingIdCounter += 1;
    return 'pending_${DateTime.now().microsecondsSinceEpoch}_$_pendingIdCounter';
  }

  List<PendingChatAttachment> _queuedPendingAttachments() {
    return _pending.where((p) => p.canSend).toList(growable: false);
  }

  void _setPendingStateByIds(
    Set<String> ids,
    PendingAttachmentState state, {
    String? error,
  }) {
    if (ids.isEmpty) return;
    for (var i = 0; i < _pending.length; i++) {
      final current = _pending[i];
      if (!ids.contains(current.clientId)) continue;
      switch (state) {
        case PendingAttachmentState.queued:
          _pending[i] = current.markQueued();
          break;
        case PendingAttachmentState.sending:
          _pending[i] = current.markSending();
          break;
        case PendingAttachmentState.failed:
          _pending[i] = current.markFailed(error);
          break;
      }
    }
  }

  int get _pendingTotalBytes {
    var total = 0;
    for (final p in _pending) {
      total += p.sizeBytes;
    }
    return total;
  }

  bool _canAttachFileSize(int sizeBytes) {
    if (sizeBytes <= 0) return true;
    if (sizeBytes > _maxSingleAttachmentBytes) {
      showGlassSnack(
        context,
        'Файл слишком большой (${_formatBytes(sizeBytes)}). Лимит: ${_formatBytes(_maxSingleAttachmentBytes)}.',
        kind: GlassSnackKind.error,
      );
      return false;
    }
    final nextTotal = _pendingTotalBytes + sizeBytes;
    if (nextTotal > _maxPendingAttachmentsBytes) {
      showGlassSnack(
        context,
        'Слишком много вложений. Лимит очереди: ${_formatBytes(_maxPendingAttachmentsBytes)}.',
        kind: GlassSnackKind.error,
      );
      return false;
    }
    return true;
  }

  Future<ChatAttachment> _resolveOptimisticAttachment(
    PendingChatAttachment attachment,
  ) async {
    final safeName = attachment.filename.isNotEmpty
        ? attachment.filename
        : 'file_${DateTime.now().millisecondsSinceEpoch}';

    final existingPath = attachment.localPath;
    if (existingPath != null && existingPath.isNotEmpty) {
      final existing = File(existingPath);
      if (await existing.exists()) {
        final size = attachment.sizeBytes > 0
            ? attachment.sizeBytes
            : await existing.length();
        return ChatAttachment(
          localPath: existingPath,
          filename: safeName,
          mimetype: attachment.mimetype,
          size: size,
        );
      }
    }

    final bytes = attachment.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Attachment bytes are missing');
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$safeName';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return ChatAttachment(
      localPath: path,
      filename: safeName,
      mimetype: attachment.mimetype,
      size: attachment.sizeBytes > 0 ? attachment.sizeBytes : bytes.length,
    );
  }

  Future<Uint8List> _readPendingAttachmentBytes(
    PendingChatAttachment attachment,
  ) async {
    final inMemory = attachment.bytes;
    if (inMemory != null && inMemory.isNotEmpty) {
      return inMemory;
    }

    final path = attachment.localPath;
    if (path == null || path.isEmpty) {
      throw StateError('Attachment path is missing');
    }
    return await File(path).readAsBytes();
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
      builder: (_) => _ChatMembersSheetBody(
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
    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;

    _myUserId ??= await _readMyUserId();

    final peerId = widget.chat.peerId ?? 0;

    if (!rt.isConnected) {
      await rt.connect();
    }

    if (_isPrivateChat && peerId > 0) {
      rt.addContacts([peerId]);
    }

    rt.joinChat(chatId);

    _rtSub ??= rt.events.listen((evt) async {
      if (evt.type == 'presence') {
        if (!_isPrivateChat) return;
        final peerId = widget.chat.peerId ?? 0;
        final userId =
            evt.data['user_id'] ?? evt.data['userId'] ?? evt.data['id'];
        if ('$userId' == '$peerId') {
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
        return;
      }

      if (evt.type == 'connection') {
        final reconnected = evt.data['reconnected'] == true;
        if (reconnected) {
          unawaited(_resyncAfterReconnect());
          unawaited(_refreshMyChatRole());
        }
        return;
      }

      if (evt.type == 'profile_updated') {
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
        return;
      }

      if (evt.type == 'member_added' ||
          evt.type == 'member_removed' ||
          evt.type == 'member_role_changed') {
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
        return;
      }

      if (evt.type == 'message_delivered') {
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
              final updated = ChatMessage(
                id: msg.id,
                chatId: msg.chatId,
                isMe: msg.isMe,
                text: msg.text,
                attachments: msg.attachments,
                sentAt: msg.sentAt,
                replyToMessageId: msg.replyToMessageId,
                isDelivered: true,
                isRead: msg.isRead,
              );
              _messages[i] = updated;
              _messageById[msg.id] = updated;
            }
          });
        }
        return;
      }

      if (evt.type == 'message_read') {
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
              final updated = ChatMessage(
                id: msg.id,
                chatId: msg.chatId,
                isMe: msg.isMe,
                text: msg.text,
                attachments: msg.attachments,
                sentAt: msg.sentAt,
                replyToMessageId: msg.replyToMessageId,
                isDelivered: true,
                isRead: true,
              );
              _messages[i] = updated;
              _messageById[msg.id] = updated;
            }
          });
        }
        return;
      }

      if (evt.type == 'message_updated') {
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
          final updated = ChatMessage(
            id: old.id,
            chatId: old.chatId,
            isMe: old.isMe,
            text: decoded.text,
            attachments: old.attachments,
            sentAt: old.sentAt,
            replyToMessageId: old.replyToMessageId,
            isDelivered: old.isDelivered,
            isRead: old.isRead,
          );

          _messages[idx] = updated;
          _messageById[incomingId] = updated;

          if (_editing?.id == incomingId) {
            _editing = null;
          }
        });
        return;
      }

      if (evt.type == 'message_deleted') {
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
        return;
      }

      if (evt.type == 'typing') {
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
        return;
      }

      if (evt.type != 'message_new') return;
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
    });
  }

  Future<int> _readMyUserId() async {
    final v = await SecureStorage.readKey(Keys.userId);
    return int.tryParse(v ?? '') ?? 0;
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
    final text = _controller.text.trim();
    final pendingToSend = _queuedPendingAttachments();
    final pendingIds = pendingToSend.map((p) => p.clientId).toSet();
    final hasAttachments = pendingToSend.isNotEmpty;
    if (text.isEmpty && !hasAttachments) return;
    if (_isPrivateChat && peerId <= 0) return;

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
      _setPendingStateByIds(pendingIds, PendingAttachmentState.sending);
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

        // optimistic replace
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == editing.id);
          if (idx >= 0) {
            final old = _messages[idx];
            _messages[idx] = ChatMessage(
              id: old.id,
              chatId: old.chatId,
              isMe: old.isMe,
              text: text,
              attachments: old.attachments,
              sentAt: old.sentAt,
              replyToMessageId: old.replyToMessageId,
              isDelivered: old.isDelivered,
              isRead: old.isRead,
            );

            _reindexMessages();
          }
        });

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

      List<ChatAttachment> optimisticAtt = const [];
      if (pendingToSend.isNotEmpty) {
        final out = <ChatAttachment>[];
        for (final p in pendingToSend) {
          out.add(await _resolveOptimisticAttachment(p));
        }
        optimisticAtt = out;
      }

      // optimistic
      setState(() {
        optimisticId = 'local_${DateTime.now().millisecondsSinceEpoch}';
        _messages.add(
          ChatMessage(
            id: optimisticId!,
            chatId: chatId.toString(),
            isMe: true,
            text: text,
            attachments: optimisticAtt,
            sentAt: DateTime.now(),
            replyToMessageId: replyTo?.id,
            isDelivered: false,
            isRead: false,
          ),
        );

        _reindexMessages();
      });

      _scheduleScrollToBottom(animated: true);

      final outgoingAttachments = <OutgoingAttachment>[];
      if (hasAttachments) {
        for (final p in pendingToSend) {
          final bytes = await _readPendingAttachmentBytes(p);
          outgoingAttachments.add(
            OutgoingAttachment(
              bytes: bytes,
              filename: p.filename,
              mimetype: p.mimetype,
            ),
          );
        }
      }

      final payload = hasAttachments
          ? await repo.buildOutgoingWsMediaMessage(
              chatId: chatId,
              chatKind: widget.chat.kind,
              peerId: peerId > 0 ? peerId : null,
              caption: text,
              attachments: outgoingAttachments,
            )
          : await repo.buildOutgoingWsTextMessage(
              chatId: chatId,
              chatKind: widget.chat.kind,
              peerId: peerId > 0 ? peerId : null,
              plaintext: text,
            );

      String wsType = 'send_message';
      if (hasAttachments) {
        final hasAudio = pendingToSend.any(
          (p) => p.mimetype.toLowerCase().startsWith('audio/'),
        );
        final hasVideo = pendingToSend.any(
          (p) => p.mimetype.toLowerCase().startsWith('video/'),
        );
        if (hasAudio && !hasVideo) {
          wsType = 'voice_message';
        } else if (hasVideo && !hasAudio) {
          wsType = 'video_message';
        }
      }

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
        _pending.removeWhere((p) => pendingIds.contains(p.clientId));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (optimisticId != null) {
          _messages.removeWhere((m) => m.id == optimisticId);
          _messageById.remove(optimisticId);
        }
        _setPendingStateByIds(
          pendingIds,
          PendingAttachmentState.failed,
          error: '$e',
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
      _scheduleScrollToBottom(animated: false);
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
    }
  }

  Future<void> _sendRecordedVoice(PendingChatAttachment attachment) async {
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
    if (chatId <= 0) return;
    if (_isPrivateChat && peerId <= 0) return;
    if (!_canAttachFileSize(attachment.sizeBytes)) return;

    final repo = context.read<ChatsRepository>();

    final safeName = attachment.filename.isNotEmpty
        ? attachment.filename
        : 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final preview = await _resolveOptimisticAttachment(attachment);
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
            bytes: await _readPendingAttachmentBytes(attachment),
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
        wsType: 'voice_message',
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
      showGlassSnack(
        context,
        'Не удалось отправить голосовое сообщение.',
        kind: GlassSnackKind.error,
      );
    }
  }

  Future<void> _sendRecordedVideo(PendingChatAttachment attachment) async {
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
    if (chatId <= 0) return;
    if (_isPrivateChat && peerId <= 0) return;
    if (!_canAttachFileSize(attachment.sizeBytes)) return;

    final repo = context.read<ChatsRepository>();

    final safeName = attachment.filename.isNotEmpty
        ? attachment.filename
        : 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final preview = await _resolveOptimisticAttachment(attachment);
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
            bytes: await _readPendingAttachmentBytes(attachment),
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
        wsType: 'video_message',
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
      showGlassSnack(
        context,
        'Не удалось отправить видео.',
        kind: GlassSnackKind.error,
      );
    }
  }

  Future<void> _pickPhotos() async {
    try {
      final files = await _picker.pickMultiImage();
      if (files.isEmpty) return;

      String mimetypeFromName(String filename) {
        final lower = filename.toLowerCase();
        if (lower.endsWith('.png')) return 'image/png';
        if (lower.endsWith('.webp')) return 'image/webp';
        if (lower.endsWith('.gif')) return 'image/gif';
        return 'image/jpeg';
      }

      final added = <PendingChatAttachment>[];
      for (final f in files) {
        final name = f.name.isNotEmpty
            ? f.name
            : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final path = f.path;
        final size = path.isNotEmpty ? await File(path).length() : 0;
        if (!_canAttachFileSize(size)) {
          continue;
        }
        added.add(
          PendingChatAttachment(
            clientId: _newPendingId(),
            filename: name,
            mimetype: mimetypeFromName(name),
            sizeBytes: size,
            localPath: path,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _pending.addAll(added);
      });
    } catch (e) {
      debugPrint('pick photos failed: $e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.camera);
      if (file == null) return;

      final name = file.name.isNotEmpty
          ? file.name
          : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final size = await File(file.path).length();
      if (!_canAttachFileSize(size)) {
        return;
      }

      if (!mounted) return;
      setState(() {
        _pending.add(
          PendingChatAttachment(
            clientId: _newPendingId(),
            filename: name,
            mimetype: 'image/jpeg',
            sizeBytes: size,
            localPath: file.path,
          ),
        );
      });
    } catch (e) {
      debugPrint('take photo failed: $e');
    }
  }

  Future<void> _pickFiles() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (res == null) return;

      final added = <PendingChatAttachment>[];
      for (final f in res.files) {
        final path = f.path;
        if (path == null || path.isEmpty) continue;
        final name = (f.name.isNotEmpty)
            ? f.name
            : 'file_${DateTime.now().millisecondsSinceEpoch}';
        final mime = lookupMimeType(path) ?? 'application/octet-stream';
        final size = (f.size > 0) ? f.size : await File(path).length();
        if (!_canAttachFileSize(size)) {
          continue;
        }

        added.add(
          PendingChatAttachment(
            clientId: _newPendingId(),
            filename: name,
            mimetype: mime,
            sizeBytes: size,
            localPath: path,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _pending.addAll(added);
      });
    } catch (e) {
      debugPrint('pick files failed: $e');
    }
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
    _rtSub?.cancel();
    _rtSub = null;
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
                  onCancelEditing: () {
                    if (_editing == null) return;
                    setState(() {
                      _editing = null;
                    });
                    _controller.clear();
                  },
                  hasReply: _replyTo != null,
                  replyText: replyText,
                  onCancelReply: () {
                    if (_replyTo == null) return;
                    setState(() {
                      _replyTo = null;
                    });
                  },
                  pending: _pending,
                  onRemovePending: (index) {
                    if (index < 0 || index >= _pending.length) return;
                    if (!_pending[index].canRemove) return;
                    setState(() {
                      _pending.removeAt(index);
                    });
                  },
                  onRetryPending: (index) {
                    if (index < 0 || index >= _pending.length) return;
                    if (!_pending[index].canRetry) return;
                    setState(() {
                      _pending[index] = _pending[index].markQueued();
                    });
                  },
                  onPickPhotos: _pickPhotos,
                  onPickFiles: _pickFiles,
                  onTakePhoto: _takePhoto,
                  onSend: _send,
                  onRecordingChanged: (mode, isRecording) {
                    if (mode == RecorderMode.video) {
                      _setVideoRecordingOverlay(show: isRecording);
                    }
                  },
                  onRecordingDurationChanged: _onVideoRecordingDurationChanged,
                  onRecordingLockedChanged: (mode, locked) {
                    if (mode != RecorderMode.video) return;
                    _onVideoRecordingLockedChanged(locked);
                  },
                  onRecorderController: (cancel, stop) {
                    _cancelVideoRecording = cancel;
                    _stopVideoRecording = stop;
                  },
                  onVideoControllerChanged: _onVideoControllerChanged,
                  onVideoActionsController: (setTorch, setUseFrontCamera) {
                    _setVideoTorch = setTorch;
                    _setVideoUseFrontCamera = setUseFrontCamera;
                  },
                  onAddRecordedFile: (attachment) async {
                    if (!mounted) return;
                    if ((attachment.mimetype).toLowerCase().startsWith(
                      'audio/',
                    )) {
                      await _sendRecordedVoice(attachment);
                      return;
                    }
                    if ((attachment.mimetype).toLowerCase().startsWith(
                      'video/',
                    )) {
                      await _sendRecordedVideo(attachment);
                      return;
                    }
                    if (!_canAttachFileSize(attachment.sizeBytes)) {
                      return;
                    }
                    setState(() {
                      _pending.add(attachment.markQueued());
                    });
                  },
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
                  onBack: () {
                    if (selectionMode) {
                      _exitSelectionMode();
                    } else {
                      Navigator.of(context).maybePop();
                    }
                  },
                  onShareSelected: () async {
                    await _forwardSelected();
                  },
                  onDeleteSelected: () {
                    final ids = Set<String>.from(selectedIds);
                    _deleteByIds(ids);
                    _deleteRemote(ids);
                  },
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
                                                                    onTap: () {
                                                                      _cancelVideoRecording
                                                                          ?.call();
                                                                    },
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
                                                                    onTap: () async {
                                                                      if (!mounted) {
                                                                        return;
                                                                      }
                                                                      final next =
                                                                          !_videoFlashEnabled;
                                                                      setState(() {
                                                                        _videoFlashEnabled =
                                                                            next;
                                                                      });
                                                                      final ok =
                                                                          await _setVideoTorch?.call(
                                                                            next,
                                                                          );
                                                                      if (ok !=
                                                                              true &&
                                                                          mounted) {
                                                                        setState(() {
                                                                          _videoFlashEnabled =
                                                                              !next;
                                                                        });
                                                                      }
                                                                    },
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
                                                                    onTap: () async {
                                                                      if (!mounted) {
                                                                        return;
                                                                      }
                                                                      final next =
                                                                          !_videoUseFrontCamera;
                                                                      setState(() {
                                                                        _videoUseFrontCamera =
                                                                            next;
                                                                      });
                                                                      final ok =
                                                                          await _setVideoUseFrontCamera?.call(
                                                                            next,
                                                                          );
                                                                      if (ok !=
                                                                              true &&
                                                                          mounted) {
                                                                        setState(() {
                                                                          _videoUseFrontCamera =
                                                                              !next;
                                                                        });
                                                                      }
                                                                    },
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
                                                                    onTap: () {
                                                                      _stopVideoRecording
                                                                          ?.call();
                                                                    },
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

    final selectedChat = await GlassOverlays.showGlassBottomSheet<ChatPreview>(
      context,
      builder: (ctx) {
        final sheetHeight = (MediaQuery.of(ctx).size.height * 0.55)
            .clamp(280.0, 560.0)
            .toDouble();
        return GlassSurface(
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: sheetHeight,
              child: ListView.builder(
                itemCount: chats.length,
                itemBuilder: (c, i) {
                  final it = chats[i];
                  return ListTile(
                    title: Text(it.user.name),
                    subtitle: Text('chat ${it.id}'),
                    onTap: () => Navigator.of(ctx).pop(it),
                  );
                },
              ),
            ),
          ),
        );
      },
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

    final canEdit = msg.isMe && msg.attachments.isEmpty;
    final selected = await RenContextMenu.show<String>(
      context,
      globalPosition: globalPosition,
      entries: [
        if (canEdit)
          RenContextMenuEntry.action(
            RenContextMenuAction<String>(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedEdit02),
              label: 'Редактировать',
              value: 'edit',
            ),
          ),
        RenContextMenuEntry.action(
          RenContextMenuAction<String>(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowTurnBackward),
            label: 'Ответить',
            value: 'reply',
          ),
        ),
        RenContextMenuEntry.action(
          RenContextMenuAction<String>(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCopy01),
            label: 'Копировать',
            value: 'copy',
          ),
        ),
        RenContextMenuEntry.action(
          RenContextMenuAction<String>(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowTurnForward),
            label: msg.attachments.isNotEmpty
                ? 'Переслать (без файлов)'
                : 'Переслать',
            value: 'share',
          ),
        ),
        RenContextMenuEntry.action(
          RenContextMenuAction<String>(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedTickDouble03),
            label: 'Выбрать',
            value: 'select',
          ),
        ),
        RenContextMenuEntry.action(
          RenContextMenuAction<String>(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02),
            label: 'Удалить',
            danger: true,
            value: 'delete',
          ),
        ),
      ],
    );

    if (!mounted) return;
    switch (selected) {
      case 'reply':
        setState(() {
          _replyTo = msg;
        });
        _focusNode.requestFocus();
        break;
      case 'edit':
        doEdit();
        break;
      case 'copy':
        await doCopy();
        break;
      case 'share':
        await doForward();
        break;
      case 'select':
        _enterSelectionMode(initial: msg);
        break;
      case 'delete':
        _deleteByIds({msg.id});
        _deleteRemote({msg.id});
        break;
      default:
        break;
    }
  }
}

class _ChatMembersSheetBody extends StatefulWidget {
  final int chatId;
  final String chatKind;
  final int myUserId;
  final ChatsRepository repo;

  const _ChatMembersSheetBody({
    required this.chatId,
    required this.chatKind,
    required this.myUserId,
    required this.repo,
  });

  @override
  State<_ChatMembersSheetBody> createState() => _ChatMembersSheetBodyState();
}

class _ChatMembersSheetBodyState extends State<_ChatMembersSheetBody> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<ChatMember> _members = const [];
  RealtimeClient? _rt;
  StreamSubscription? _rtSub;
  Timer? _realtimeReloadDebounce;

  final TextEditingController _memberIdCtrl = TextEditingController();
  final TextEditingController _memberSearchCtrl = TextEditingController();
  String _newMemberRole = 'member';
  Timer? _memberSearchDebounce;
  int _memberSearchSeq = 0;
  bool _memberSearching = false;
  String? _memberSearchError;
  List<ChatUser> _memberSearchResults = const [];

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  bool get _canManage {
    final me = _members
        .where((m) => m.userId == widget.myUserId)
        .cast<ChatMember?>()
        .firstWhere((m) => m != null, orElse: () => null);
    if (me == null) return false;
    final role = me.role.trim().toLowerCase();
    return role == 'owner' || role == 'admin';
  }

  @override
  void initState() {
    super.initState();
    _reload();
    _ensureRealtime();
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _realtimeReloadDebounce?.cancel();
    _memberSearchDebounce?.cancel();
    _memberSearchCtrl.dispose();
    _memberIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload({bool withLoading = true}) async {
    if (!mounted) return;
    if (withLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final members = await widget.repo.listMembers(widget.chatId);
      if (!mounted) return;
      setState(() {
        _members = members;
        if (withLoading) {
          _loading = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (withLoading) {
          _loading = false;
        }
        _error = '$e';
      });
    }
  }

  Future<void> _ensureRealtime() async {
    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;

    if (!rt.isConnected) {
      await rt.connect();
    }

    _rtSub ??= rt.events.listen((evt) {
      final t = evt.type;
      if (t != 'member_added' &&
          t != 'member_removed' &&
          t != 'member_role_changed') {
        return;
      }

      final evtChatId = _asInt(evt.data['chat_id'] ?? evt.data['chatId']);
      if (evtChatId != widget.chatId) return;

      final removedUserId = _asInt(evt.data['user_id'] ?? evt.data['userId']);
      if (t == 'member_removed' && removedUserId == widget.myUserId) {
        if (!mounted) return;
        showGlassSnack(
          context,
          'Вы были удалены из этого чата',
          kind: GlassSnackKind.info,
        );
        Navigator.of(context).maybePop();
        return;
      }

      _realtimeReloadDebounce?.cancel();
      _realtimeReloadDebounce = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        _reload(withLoading: false);
      });
    });
  }

  Set<int> _existingMemberIds() {
    return _members.map((m) => m.userId).toSet();
  }

  void _runMemberSearch(String query) {
    final q = query.trim();
    final seq = ++_memberSearchSeq;
    if (q.isEmpty) {
      setState(() {
        _memberSearching = false;
        _memberSearchError = null;
        _memberSearchResults = const [];
      });
      return;
    }

    setState(() {
      _memberSearching = true;
      _memberSearchError = null;
    });

    widget.repo
        .searchUsers(q)
        .then((users) {
          if (!mounted || seq != _memberSearchSeq) return;
          final existing = _existingMemberIds();
          final filtered = users
              .where((u) => !existing.contains(int.tryParse(u.id) ?? 0))
              .toList(growable: false);
          setState(() {
            _memberSearching = false;
            _memberSearchError = null;
            _memberSearchResults = filtered;
          });
        })
        .catchError((e) {
          if (!mounted || seq != _memberSearchSeq) return;
          setState(() {
            _memberSearching = false;
            _memberSearchError = e.toString();
            _memberSearchResults = const [];
          });
        });
  }

  void _scheduleMemberSearch(String query) {
    _memberSearchDebounce?.cancel();
    _memberSearchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      _runMemberSearch(query);
    });
  }

  Future<void> _addMember() async {
    if (!_canManage || _busy) return;
    final userId = int.tryParse(_memberIdCtrl.text.trim()) ?? 0;
    if (userId <= 0) {
      showGlassSnack(
        context,
        'Укажите корректный ID пользователя',
        kind: GlassSnackKind.error,
      );
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      await widget.repo.addMember(
        widget.chatId,
        userId: userId,
        role: _newMemberRole,
      );
      _memberIdCtrl.clear();
      _memberSearchCtrl.clear();
      _memberSearchResults = const [];
      _memberSearchError = null;
      await _reload();
      if (!mounted) return;
      showGlassSnack(
        context,
        'Участник добавлен',
        kind: GlassSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, '$e', kind: GlassSnackKind.error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _setRole(ChatMember member, String role) async {
    if (!_canManage || _busy) return;
    setState(() {
      _busy = true;
    });
    try {
      await widget.repo.updateMemberRole(
        widget.chatId,
        userId: member.userId,
        role: role,
      );
      await _reload();
      if (!mounted) return;
      showGlassSnack(
        context,
        'Роль обновлена (${member.username})',
        kind: GlassSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, '$e', kind: GlassSnackKind.error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _removeMember(ChatMember member) async {
    if (!_canManage || _busy) return;
    if (member.userId == widget.myUserId) {
      showGlassSnack(
        context,
        'Себя через этот sheet удалить нельзя',
        kind: GlassSnackKind.info,
      );
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      await widget.repo.removeMember(widget.chatId, userId: member.userId);
      await _reload();
      if (!mounted) return;
      showGlassSnack(
        context,
        'Участник удалён (${member.username})',
        kind: GlassSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, '$e', kind: GlassSnackKind.error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  String _roleLabel(String role) {
    switch (role.trim().toLowerCase()) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      default:
        return 'Member';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return DraggableScrollableSheet(
      initialChildSize: 0.74,
      minChildSize: 0.45,
      maxChildSize: 0.95,
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
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
                widget.chatKind == 'channel'
                    ? 'Участники канала'
                    : 'Участники группы',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Всего: ${_members.length} • '
                '${_canManage ? "у вас есть права управления" : "только просмотр"}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.72),
                ),
              ),
              const SizedBox(height: 12),
              if (_canManage) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _memberIdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'ID участника',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _newMemberRole,
                      items: const [
                        DropdownMenuItem(
                          value: 'member',
                          child: Text('member'),
                        ),
                        DropdownMenuItem(value: 'admin', child: Text('admin')),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() {
                                _newMemberRole = v;
                              });
                            },
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _addMember,
                      child: const Text('Добавить'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _memberSearchCtrl,
                  onChanged: _scheduleMemberSearch,
                  decoration: InputDecoration(
                    labelText: 'Поиск пользователя (username / ID)',
                    suffixIcon: _memberSearchCtrl.text.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    _memberSearchCtrl.clear();
                                    _memberSearchDebounce?.cancel();
                                    setState(() {
                                      _memberSearching = false;
                                      _memberSearchError = null;
                                      _memberSearchResults = const [];
                                    });
                                  },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                if (_memberSearching)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                else if (_memberSearchError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _memberSearchError!.replaceFirst('Exception: ', ''),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  )
                else if (_memberSearchResults.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      children: _memberSearchResults
                          .map((u) {
                            final uid = int.tryParse(u.id) ?? 0;
                            if (uid <= 0) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassSurface(
                                borderRadius: 14,
                                blurSigma: 8,
                                borderColor: baseInk.withOpacity(
                                  isDark ? 0.14 : 0.08,
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    RenAvatar(
                                      url: u.avatarUrl,
                                      name: u.name,
                                      isOnline: false,
                                      size: 34,
                                      onlineDotSize: 0,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            u.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          Text(
                                            'ID: $uid',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
                                                      .withOpacity(0.7),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () async {
                                              _memberIdCtrl.text = '$uid';
                                              await _addMember();
                                            },
                                      child: const Text('Add'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    _error!.replaceFirst('Exception: ', ''),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                )
              else if (_members.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Список участников пуст',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                )
              else
                ..._members.map((member) {
                  final role = member.role.trim().toLowerCase();
                  final canChangeRole =
                      _canManage &&
                      member.userId != widget.myUserId &&
                      role != 'owner';
                  final canRemove = canChangeRole;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassSurface(
                      borderRadius: 16,
                      blurSigma: 10,
                      borderColor: baseInk.withOpacity(isDark ? 0.16 : 0.09),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(
                        children: [
                          RenAvatar(
                            url: member.avatarUrl,
                            name: member.username,
                            isOnline: false,
                            size: 38,
                            onlineDotSize: 0,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${member.userId} • ${_roleLabel(member.role)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.72),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (canChangeRole)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded),
                              onSelected: (value) async {
                                if (value == 'remove') {
                                  await _removeMember(member);
                                  return;
                                }
                                await _setRole(member, value);
                              },
                              itemBuilder: (_) => [
                                if (role != 'admin')
                                  const PopupMenuItem<String>(
                                    value: 'admin',
                                    child: Text('Сделать admin'),
                                  ),
                                if (role != 'member')
                                  const PopupMenuItem<String>(
                                    value: 'member',
                                    child: Text('Сделать member'),
                                  ),
                                if (canRemove)
                                  const PopupMenuItem<String>(
                                    value: 'remove',
                                    child: Text('Удалить из чата'),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
