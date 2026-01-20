import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:mime/mime.dart';
import 'package:flutter/services.dart';

import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/shared/widgets/background.dart';
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

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  final List<ChatMessage> _messages = [];
  final Map<String, ChatMessage> _messageById = {};

  ChatMessage? _replyTo;
  ChatMessage? _editing;

  String? _pressedMessageId;

  bool _selectionMode = false;
  final Set<String> _selectedMessageIds = {};

  final _picker = ImagePicker();

  final List<PendingChatAttachment> _pending = [];

  int? _myUserId;

  bool _peerOnline = false;
  bool _peerTyping = false;
  Timer? _typingDebounce;

  bool _isAtBottom = true;

  double _lastViewInsetsBottom = 0;

  RealtimeClient? _rt;
  StreamSubscription? _rtSub;

  Timer? _loadOlderDebounce;

  bool _showVideoRecordingOverlay = false;
  String _videoRecordingDurationText = '0:00';
  bool _videoFlashEnabled = false;
  bool _videoUseFrontCamera = false;
  bool _videoRecordingLocked = false;
  VoidCallback? _cancelVideoRecording;
  VoidCallback? _stopVideoRecording;
  late final AnimationController _videoProgressController;
  late final AnimationController _videoLockedTransition;
  late final AnimationController _videoPulse;

  void _setVideoRecordingOverlay({required bool show}) {
    if (!mounted) return;
    setState(() {
      _showVideoRecordingOverlay = show;
      if (!show) {
        _videoRecordingDurationText = '0:00';
        _videoFlashEnabled = false;
        _videoUseFrontCamera = false;
        _videoRecordingLocked = false;
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

  void _reindexMessages() {
    _messageById
      ..clear()
      ..addEntries(_messages.map((m) => MapEntry(m.id, m)));
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

  @override
  void initState() {
    super.initState();
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
    _peerOnline = widget.chat.user.isOnline;
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    _scrollController.addListener(_onScroll);
    _init();
  }

  void _scheduleScrollToBottom({required bool animated}) {
    // Scroll can be requested before ListView reports correct maxScrollExtent.
    // Retry a few times after layout to ensure we end up at the bottom.
    void attempt(int left) {
      _scrollToBottom(animated: animated);
      if (left <= 0) return;

      Future.delayed(const Duration(milliseconds: 60), () {
        if (!mounted) return;
        if (!_scrollController.hasClients) return;
        final pos = _scrollController.position;
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
  }

  Future<void> _loadOlder() async {
    if (_loading || _loadingMore || !_hasMore) return;
    if (_messages.isEmpty) return;

    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    final beforeId = int.tryParse(_messages.first.id) ?? 0;
    if (beforeId <= 0) return;

    final repo = context.read<ChatsRepository>();

    final oldPixels = _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
    final oldMax = _scrollController.hasClients ? _scrollController.position.maxScrollExtent : 0.0;

    setState(() {
      _loadingMore = true;
    });

    try {
      final list = await repo.fetchMessages(chatId, limit: 50, beforeId: beforeId);
      if (!mounted) return;

      if (list.isEmpty) {
        setState(() {
          _hasMore = false;
          _loadingMore = false;
        });
        return;
      }

      final existingIds = _messages.map((e) => e.id).toSet();
      final toAdd = <ChatMessage>[];
      for (final m in list) {
        if (!existingIds.contains(m.id)) {
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
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    final rt = _rt;
    if (rt == null || !rt.isConnected) return;
    rt.typing(chatId, isTyping);
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

    try {
      final list = await repo.fetchMessages(chatId, limit: 50);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _reindexMessages();
        _loading = false;
        _hasMore = true;
      });
      _scheduleScrollToBottom(animated: false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }

    await _ensureRealtime();
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

    if (peerId > 0) {
      rt.init(contacts: [peerId]);
    }

    rt.joinChat(chatId);

    _rtSub ??= rt.events.listen((evt) async {
      if (evt.type == 'presence') {
        final peerId = widget.chat.peerId ?? 0;
        final userId = evt.data['user_id'] ?? evt.data['userId'] ?? evt.data['id'];
        if ('$userId' == '$peerId') {
          final statusRaw = (evt.data['status'] ??
                  evt.data['state'] ??
                  evt.data['online'] ??
                  evt.data['is_online'] ??
                  evt.data['isOnline'])
              .toString()
              .trim()
              .toLowerCase();
          final online = statusRaw == 'online' || statusRaw == 'true' || statusRaw == '1';
          if (online != _peerOnline && mounted) {
            setState(() {
              _peerOnline = online;
            });
          }
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
          final idx = _messages.indexWhere((x) => x.id == incomingId);
          if (idx < 0) return;
          final old = _messages[idx];
          _messages[idx] = ChatMessage(
            id: old.id,
            chatId: old.chatId,
            isMe: old.isMe,
            text: decoded.text,
            attachments: old.attachments,
            sentAt: old.sentAt,
            replyToMessageId: old.replyToMessageId,
          );

          _reindexMessages();

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
          _messages.removeWhere((m) => m.id == messageId.toString());
          _reindexMessages();
          _selectedMessageIds.removeWhere((id) => id == messageId.toString());
          if (_selectedMessageIds.isEmpty) {
            _selectionMode = false;
          }
          if (_replyTo?.id == messageId.toString()) {
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
              msg.entries.map(
                (e) => MapEntry(e.key.toString(), e.value),
              ),
            );

      debugPrint('WS message keys: ${m.keys.toList()}');
      final encPreview = (m['message'] is String)
          ? (m['message'] as String)
          : (m['body'] is String ? (m['body'] as String) : '');
      if (encPreview.isNotEmpty) {
        debugPrint('WS message encrypted preview: ${encPreview.substring(0, encPreview.length > 200 ? 200 : encPreview.length)}');
      }

      final decoded = await repo.decryptIncomingWsMessageFull(message: m);

      final senderId = m['sender_id'] is int
          ? m['sender_id'] as int
          : int.tryParse('${m['sender_id']}') ?? 0;
      final createdAtStr = (m['created_at'] as String?) ?? '';
      final createdAt = (DateTime.tryParse(createdAtStr) ?? DateTime.now()).toLocal();

      final replyDyn = m['reply_to_message_id'] ?? m['replyToMessageId'];
      final replyId = (replyDyn is int)
          ? replyDyn
          : int.tryParse('${replyDyn ?? ''}');

      final myId = _myUserId ?? 0;
      final isMe = (myId > 0) ? senderId == myId : senderId != peerId;

      debugPrint('WS message_new chat=$chatId sender=$senderId my=$myId peer=$peerId isMe=$isMe id=${m['id']}');

      if (!mounted) return;
      setState(() {
        final incomingId = '${m['id'] ?? ''}';
        if (incomingId.isNotEmpty && _messages.any((x) => x.id == incomingId)) {
          return;
        }

        // если это echo нашего сообщения, попробуем убрать последний optimistic дубль
        if (isMe && _messages.isNotEmpty) {
          final last = _messages.last;
          if (last.id.startsWith('local_') && last.text == decoded.text) {
            _messages.removeLast();
          }
        }

        _messages.add(
          ChatMessage(
            id: '${m['id'] ?? DateTime.now().millisecondsSinceEpoch}',
            chatId: chatId.toString(),
            isMe: isMe,
            text: decoded.text,
            attachments: decoded.attachments,
            sentAt: createdAt,
            replyToMessageId: (replyId != null && replyId > 0) ? replyId.toString() : null,
          ),
        );

        _reindexMessages();
      });

      if (isMe || _isAtBottom) {
        _scheduleScrollToBottom(animated: true);
      }
    });
  }

  Future<int> _readMyUserId() async {
    final v = await SecureStorage.readKey(Keys.UserId);
    return int.tryParse(v ?? '') ?? 0;
  }

  Future<void> _send() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    final peerId = widget.chat.peerId ?? 0;
    final text = _controller.text.trim();
    final hasAttachments = _pending.isNotEmpty;
    if (text.isEmpty && !hasAttachments) return;
    if (peerId <= 0) return;

    final repo = context.read<ChatsRepository>();
    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;

    _typingDebounce?.cancel();
    _sendTyping(false);

    final pendingCopy = List<PendingChatAttachment>.from(_pending);

    final replyTo = _replyTo;
    final editing = _editing;
    setState(() {
      _pending.clear();
      _replyTo = null;
      _editing = null;
    });
    _controller.clear();

    if (editing != null) {
      // редактирование: поддерживаем только текст без файлов
      if (hasAttachments || pendingCopy.isNotEmpty || editing.attachments.isNotEmpty) {
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
          );

          _reindexMessages();
        }
      });

      final payload = await repo.buildEncryptedWsMessage(
        chatId: chatId,
        peerId: peerId,
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
    if (pendingCopy.isNotEmpty) {
      final dir = await getTemporaryDirectory();
      final out = <ChatAttachment>[];
      for (final p in pendingCopy) {
        final safeName = p.filename.isNotEmpty
            ? p.filename
            : 'file_${DateTime.now().millisecondsSinceEpoch}';
        final path = '${dir.path}/$safeName';
        final f = File(path);
        await f.writeAsBytes(p.bytes, flush: true);
        out.add(
          ChatAttachment(
            localPath: path,
            filename: safeName,
            mimetype: p.mimetype,
            size: p.bytes.length,
          ),
        );
      }
      optimisticAtt = out;
    }

    // optimistic
    setState(() {
      _messages.add(
        ChatMessage(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
          chatId: chatId.toString(),
          isMe: true,
          text: text,
          attachments: optimisticAtt,
          sentAt: DateTime.now(),
          replyToMessageId: replyTo?.id,
        ),
      );

      _reindexMessages();
    });

    _scheduleScrollToBottom(animated: true);

    final payload = hasAttachments
        ? await repo.buildEncryptedWsMediaMessage(
            chatId: chatId,
            peerId: peerId,
            caption: text,
            attachments: pendingCopy
                .map(
                  (p) => OutgoingAttachment(
                    bytes: p.bytes,
                    filename: p.filename,
                    mimetype: p.mimetype,
                  ),
                )
                .toList(),
          )
        : await repo.buildEncryptedWsMessage(
            chatId: chatId,
            peerId: peerId,
            plaintext: text,
          );

    if (!rt.isConnected) {
      await rt.connect();
    }
    rt.joinChat(chatId);

    rt.sendMessage(
      chatId: chatId,
      message: payload['message'] as String,
      messageType: payload['message_type'] as String?,
      envelopes: payload['envelopes'] as Map<String, dynamic>?,
      metadata: payload['metadata'] as List<dynamic>?,
      replyToMessageId: replyTo == null ? null : int.tryParse(replyTo.id),
    );
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
        final bytes = await f.readAsBytes();
        final name = f.name.isNotEmpty
            ? f.name
            : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        added.add(
          PendingChatAttachment(
            bytes: bytes,
            filename: name,
            mimetype: mimetypeFromName(name),
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
      final file = await _picker.pickImage(
        source: ImageSource.camera,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;

      final name = file.name.isNotEmpty
          ? file.name
          : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';

      if (!mounted) return;
      setState(() {
        _pending.add(
          PendingChatAttachment(
            bytes: bytes,
            filename: name,
            mimetype: 'image/jpeg',
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
        withData: true,
      );
      if (res == null) return;

      final added = <PendingChatAttachment>[];
      for (final f in res.files) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final name = (f.name.isNotEmpty)
            ? f.name
            : 'file_${DateTime.now().millisecondsSinceEpoch}';
        final mime = lookupMimeType(f.path ?? '') ?? 'application/octet-stream';

        added.add(
          PendingChatAttachment(
            bytes: bytes,
            filename: name,
            mimetype: mime,
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
    _videoProgressController.dispose();
    _videoLockedTransition.dispose();
    _videoPulse.dispose();
    _typingDebounce?.cancel();
    _typingDebounce = null;
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
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: true,
        appBar: ChatPageAppBar(
          chat: widget.chat,
          selectionMode: _selectionMode,
          selectedCount: _selectedMessageIds.length,
          peerOnline: _peerOnline,
          peerTyping: _peerTyping,
          onBack: () {
            if (_selectionMode) {
              _exitSelectionMode();
            } else {
              Navigator.of(context).maybePop();
            }
          },
          onShareSelected: () async {
            await _forwardSelected();
          },
          onDeleteSelected: () {
            final ids = Set<String>.from(_selectedMessageIds);
            _deleteByIds(ids);
            _deleteRemote(ids);
          },
          onMenu: () {},
        ),
        body: Builder(
          builder: (context) {
            final media = MediaQuery.of(context);
            const double inputHeight = 44;
            const double horizontalPadding = 14;
            const double verticalPadding = 14;

            final double topInset = media.padding.top;
            // viewInsets.bottom is already applied via AnimatedPadding below.
            final double bottomInset = media.padding.bottom;

            final double listTopPadding = topInset + kToolbarHeight + 12;
            final double listBottomPadding =
                bottomInset + inputHeight + verticalPadding + 12;

            final messages = _messages;

            final insetsBottom = media.viewInsets.bottom;
            if (_focusNode.hasFocus && _isAtBottom && insetsBottom != _lastViewInsetsBottom) {
              _lastViewInsetsBottom = insetsBottom;
              _scheduleScrollToBottom(animated: false);
            } else {
              _lastViewInsetsBottom = insetsBottom;
            }

            final replyText = _replyTo == null ? '' : _messageSummary(_replyTo!);

            return Stack(
              children: [
                Positioned.fill(
                  child: _loading ? ListView.separated(
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
                        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
                        child: ChatSkeletonMessageBubble(isMe: alignRight),
                      );
                    },
                  ) : ListView.separated(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      listTopPadding,
                      horizontalPadding,
                      listBottomPadding,
                    ),
                    itemCount: messages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final replied = _findMessageById(msg.replyToMessageId);
                      final replyPreview = (replied == null) ? null : _messageSummary(replied).trim();
                      final selected = _selectionMode && _selectedMessageIds.contains(msg.id);
                      final pressed = _pressedMessageId == msg.id;
                      return Align(
                        alignment: msg.isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Dismissible(
                          key: ValueKey('reply_${msg.id}'),
                          direction: _selectionMode
                              ? DismissDirection.none
                              : (msg.isMe ? DismissDirection.endToStart : DismissDirection.startToEnd),
                          movementDuration: const Duration(milliseconds: 260),
                          dismissThresholds: {
                            DismissDirection.startToEnd: 0.22,
                            DismissDirection.endToStart: 0.22,
                          },
                          confirmDismiss: (_) async {
                            if (_selectionMode) return false;
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
                            alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Icon(
                                Icons.reply,
                                size: 18,
                                color: theme.colorScheme.onSurface.withOpacity(0.55),
                              ),
                            ),
                          ),
                          secondaryBackground: Align(
                            alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Icon(
                                Icons.reply,
                                size: 18,
                                color: theme.colorScheme.onSurface.withOpacity(0.55),
                              ),
                            ),
                          ),
                          child: GestureDetector(
                            onTapDown: (_) {
                              if (!mounted) return;
                              setState(() {
                                _pressedMessageId = msg.id;
                              });
                            },
                            onTapCancel: () {
                              if (!mounted) return;
                              setState(() {
                                if (_pressedMessageId == msg.id) {
                                  _pressedMessageId = null;
                                }
                              });
                            },
                            onTapUp: (_) {
                              if (!mounted) return;
                              setState(() {
                                if (_pressedMessageId == msg.id) {
                                  _pressedMessageId = null;
                                }
                              });
                            },
                            onTap: () {
                              if (_selectionMode) {
                                _toggleSelected(msg);
                              }
                            },
                            onLongPressStart: (d) async {
                              HapticFeedback.selectionClick();
                              if (mounted) {
                                setState(() {
                                  _pressedMessageId = msg.id;
                                });
                              }
                              if (_selectionMode) {
                                _toggleSelected(msg);
                              } else {
                                await _showMessageContextMenu(msg, d.globalPosition);
                              }

                              if (mounted) {
                                setState(() {
                                  if (_pressedMessageId == msg.id) {
                                    _pressedMessageId = null;
                                  }
                                });
                              }
                            },
                            onLongPressEnd: (_) {
                              if (!mounted) return;
                              setState(() {
                                if (_pressedMessageId == msg.id) {
                                  _pressedMessageId = null;
                                }
                              });
                            },
                            child: AnimatedScale(
                              scale: pressed ? 0.985 : (selected ? 1.3 : 1.0),
                              duration: const Duration(milliseconds: 110),
                              curve: Curves.easeOut,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 110),
                                    curve: Curves.easeOut,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      color: pressed
                                          ? theme.colorScheme.onSurface.withOpacity(isDark ? 0.10 : 0.06)
                                          : (selected
                                              ? theme.colorScheme.primary.withOpacity(isDark ? 0.12 : 0.10)
                                              : Colors.transparent),
                                      border: selected
                                          ? Border.all(
                                              color: theme.colorScheme.primary.withOpacity(0.8),
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
                                      duration: const Duration(milliseconds: 120),
                                      curve: Curves.easeOut,
                                      child: AnimatedScale(
                                        scale: selected ? 1 : 0.9,
                                        duration: const Duration(milliseconds: 120),
                                        curve: Curves.easeOut,
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: theme.colorScheme.surface.withOpacity(0.9),
                                              width: 1,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.check,
                                            size: 14,
                                            color: theme.colorScheme.onPrimary,
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
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                    child: SafeArea(
                      top: false,
                      child: ChatInputBar(
                        controller: _controller,
                        focusNode: _focusNode,
                        isDark: isDark,
                        isEditing: _editing != null,
                        onCancelEditing: () {
                          setState(() {
                            _editing = null;
                          });
                          _controller.clear();
                        },
                        hasReply: _replyTo != null,
                        replyText: replyText,
                        onCancelReply: () {
                          setState(() {
                            _replyTo = null;
                          });
                        },
                        pending: _pending,
                        onRemovePending: (index) {
                          setState(() {
                            _pending.removeAt(index);
                          });
                        },
                        onPickPhotos: () async => await _pickPhotos(),
                        onPickFiles: () async => await _pickFiles(),
                        onTakePhoto: () async => await _takePhoto(),
                        onSend: _send,
                        onRecordingChanged: (mode, isRecording) {
                          if (mode == RecorderMode.video) {
                            _setVideoRecordingOverlay(show: isRecording);
                          }
                        },
                        onRecordingDurationChanged: (t) {
                          if (!_showVideoRecordingOverlay) return;
                          if (!mounted) return;
                          setState(() {
                            _videoRecordingDurationText = t;
                          });
                        },
                        onRecordingLockedChanged: (mode, locked) {
                          if (mode != RecorderMode.video) return;
                          if (!mounted) return;
                          setState(() {
                            _videoRecordingLocked = locked;
                          });

                          if (locked) {
                            _videoLockedTransition.forward();
                          } else {
                            _videoLockedTransition.reverse();
                          }
                        },
                        onRecorderController: (cancel, stop) {
                          _cancelVideoRecording = cancel;
                          _stopVideoRecording = stop;
                        },
                        onAddRecordedFile: (attachment) async {
                          if (!mounted) return;
                          setState(() {
                            _pending.add(attachment);
                          });
                        },
                      ),
                    ),
                  ),
                ),

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
                                final t = Curves.easeOut.transform(_videoLockedTransition.value);
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
                                  final t = Curves.easeOutBack.transform(_videoLockedTransition.value);
                                  final pulse = _videoPulse.value;
                                  final breathe = math.sin(pulse * math.pi * 2);
                                  final breathingScale = 1 + 0.006 * breathe;
                                  final scale = (1 - 0.02 * t) * breathingScale;
                                  final dy = -8.0 * t;
                                  return Transform.translate(
                                    offset: Offset(0, dy),
                                    child: Transform.scale(
                                      scale: scale,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(32),
                                        child: Container(
                                          width: 320,
                                          height: 320,
                                          color: theme.colorScheme.surface.withOpacity(isDark ? 0.55 : 0.80),
                                          child: Stack(
                                            children: [
                                              Center(
                                                child: HugeIcon(
                                                  icon: HugeIcons.strokeRoundedVideo01,
                                                  size: 92,
                                                  color: theme.colorScheme.onSurface.withOpacity(0.85),
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
                                  final t = Curves.easeOut.transform(_videoLockedTransition.value);
                                  final capsuleScale = 1 + 0.01 * t;
                                  final capsuleDy = -4.0 * t;
                                  return Transform.translate(
                                    offset: Offset(0, capsuleDy),
                                    child: Transform.scale(
                                      scale: capsuleScale,
                                      child: GlassSurface(
                                        borderRadius: 999,
                                        blurSigma: 12,
                                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                        child: SizedBox(
                                          width: 320,
                                          child: Row(
                                            children: [
                                              AnimatedSwitcher(
                                                duration: const Duration(milliseconds: 220),
                                                switchInCurve: Curves.easeOut,
                                                switchOutCurve: Curves.easeOut,
                                                transitionBuilder: (child, anim) {
                                                  final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                                                  return FadeTransition(
                                                    opacity: curved,
                                                    child: ScaleTransition(
                                                      scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
                                                      child: SlideTransition(
                                                        position: Tween<Offset>(
                                                          begin: const Offset(-0.10, 0),
                                                          end: Offset.zero,
                                                        ).animate(curved),
                                                        child: child,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: _videoRecordingLocked
                                                    ? Row(
                                                        key: const ValueKey('locked_cancel'),
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          GestureDetector(
                                                            onTap: () {
                                                              _cancelVideoRecording?.call();
                                                            },
                                                            child: GlassSurface(
                                                              borderRadius: 12,
                                                              blurSigma: 12,
                                                              width: 32,
                                                              height: 32,
                                                              child: Center(
                                                                child: HugeIcon(
                                                                  icon: HugeIcons.strokeRoundedCancel01,
                                                                  size: 20,
                                                                  color: theme.colorScheme.onSurface.withOpacity(0.9),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 10),
                                                        ],
                                                      )
                                                    : const SizedBox(
                                                        key: ValueKey('hold_cancel_spacer'),
                                                      ),
                                              ),
                                              AnimatedBuilder(
                                                animation: _videoPulse,
                                                builder: (context, _) {
                                                  final p = Curves.easeInOut.transform(_videoPulse.value);
                                                  final s = 1.0 + 0.18 * p;
                                                  final o = 0.55 + 0.45 * (1 - p);
                                                  return Transform.scale(
                                                    scale: s,
                                                    child: Container(
                                                      width: 8,
                                                      height: 8,
                                                      decoration: BoxDecoration(
                                                        color: theme.colorScheme.error.withOpacity(o),
                                                        shape: BoxShape.circle,
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: theme.colorScheme.error.withOpacity(0.35 * o),
                                                            blurRadius: 10 + 10 * p,
                                                            spreadRadius: 0.5 + 0.8 * p,
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
                                                style: theme.textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: theme.colorScheme.onSurface,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: AnimatedBuilder(
                                                  animation: _videoProgressController,
                                                  builder: (context, _) {
                                                    return ClipRRect(
                                                      borderRadius: BorderRadius.circular(999),
                                                      child: Container(
                                                        height: 4,
                                                        color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.18 : 0.12),
                                                        alignment: Alignment.centerLeft,
                                                        child: FractionallySizedBox(
                                                          widthFactor: _videoProgressController.value.clamp(0.0, 1.0),
                                                          child: Container(
                                                            color: theme.colorScheme.primary,
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              AnimatedSwitcher(
                                                duration: const Duration(milliseconds: 220),
                                                switchInCurve: Curves.easeOut,
                                                switchOutCurve: Curves.easeOut,
                                                transitionBuilder: (child, anim) {
                                                  final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                                                  return FadeTransition(
                                                    opacity: curved,
                                                    child: ScaleTransition(
                                                      scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
                                                      child: SlideTransition(
                                                        position: Tween<Offset>(
                                                          begin: const Offset(0.12, 0),
                                                          end: Offset.zero,
                                                        ).animate(curved),
                                                        child: child,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: _videoRecordingLocked
                                                    ? Row(
                                                        key: const ValueKey('locked_actions'),
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const SizedBox(width: 10),
                                                          GestureDetector(
                                                            onTap: () {
                                                              if (!mounted) return;
                                                              setState(() {
                                                                _videoFlashEnabled = !_videoFlashEnabled;
                                                              });
                                                            },
                                                            child: GlassSurface(
                                                              borderRadius: 12,
                                                              blurSigma: 12,
                                                              width: 32,
                                                              height: 32,
                                                              child: Center(
                                                                child: HugeIcon(
                                                                  icon: _videoFlashEnabled
                                                                      ? HugeIcons.strokeRoundedFlash
                                                                      : HugeIcons.strokeRoundedFlashOff,
                                                                  size: 20,
                                                                  color: theme.colorScheme.onSurface.withOpacity(0.9),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          GestureDetector(
                                                            onTap: () {
                                                              if (!mounted) return;
                                                              setState(() {
                                                                _videoUseFrontCamera = !_videoUseFrontCamera;
                                                              });
                                                            },
                                                            child: GlassSurface(
                                                              borderRadius: 12,
                                                              blurSigma: 12,
                                                              width: 32,
                                                              height: 32,
                                                              child: Center(
                                                                child: HugeIcon(
                                                                  icon: HugeIcons.strokeRoundedExchange01,
                                                                  size: 20,
                                                                  color: theme.colorScheme.onSurface.withOpacity(0.9),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          GestureDetector(
                                                            onTap: () {
                                                              _stopVideoRecording?.call();
                                                            },
                                                            child: GlassSurface(
                                                              borderRadius: 12,
                                                              blurSigma: 12,
                                                              width: 32,
                                                              height: 32,
                                                              child: Center(
                                                                child: HugeIcon(
                                                                  icon: HugeIcons.strokeRoundedSent,
                                                                  size: 20,
                                                                  color: theme.colorScheme.onSurface.withOpacity(0.9),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                    : const SizedBox(
                                                        key: ValueKey('hold_actions_spacer'),
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
      ),
    );
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
        isDark: isDark,
      );
    }

    if (_isSquareVideoMessage(msg)) {
      final videoPath = msg.attachments.first.localPath;
      return SquareVideoBubble(
        videoPath: videoPath,
        timeLabel: _formatTime(msg.sentAt),
        isMe: msg.isMe,
        isDark: isDark,
      );
    }

    // Обычное сообщение (текст, фото, файлы, обычное видео)
    return ChatMessageBubble(
      replyPreview: (replyPreview != null && replyPreview.isNotEmpty)
          ? replyPreview
          : null,
      text: msg.text,
      attachments: msg.attachments,
      timeLabel: _formatTime(msg.sentAt),
      isMe: msg.isMe,
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


  void _enterSelectionMode({ChatMessage? initial}) {
    if (!mounted) return;
    setState(() {
      _selectionMode = true;
      if (initial != null) {
        _selectedMessageIds.add(initial.id);
      }
    });
  }

  void _exitSelectionMode() {
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _toggleSelected(ChatMessage msg) {
    if (!mounted) return;
    setState(() {
      if (_selectedMessageIds.contains(msg.id)) {
        _selectedMessageIds.remove(msg.id);
      } else {
        _selectedMessageIds.add(msg.id);
      }
      if (_selectedMessageIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _deleteByIds(Set<String> ids) {
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((m) => ids.contains(m.id));
      _selectedMessageIds.removeWhere((id) => !_messages.any((m) => m.id == id));
      if (_selectedMessageIds.isEmpty) {
        _selectionMode = false;
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
        return GlassSurface(
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.55,
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
    if (toChatId <= 0 || toPeerId <= 0) {
      showGlassSnack(
        context,
        'Пересылка поддерживается только для private чатов',
        kind: GlassSnackKind.info,
      );
      return;
    }

    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;

    final ids = List<String>.from(_selectedMessageIds);
    ids.sort((a, b) => a.compareTo(b));

    for (final id in ids) {
      final mid = int.tryParse(id);
      if (mid == null || mid <= 0) continue;
      final msg = _messages.where((m) => m.id == id).cast<ChatMessage?>().firstWhere(
            (m) => m != null,
            orElse: () => null,
          );
      if (msg == null) continue;
      if (msg.attachments.isNotEmpty) continue;
      final payload = await repo.buildEncryptedWsMessage(
        chatId: toChatId,
        peerId: toPeerId,
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

  Future<void> _showMessageContextMenu(ChatMessage msg, Offset globalPosition) async {
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
            label: msg.attachments.isNotEmpty ? 'Переслать (без файлов)' : 'Переслать',
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