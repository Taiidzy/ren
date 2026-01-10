import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:mime/mime.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/shared/widgets/background.dart';
import 'package:ren/shared/widgets/avatar.dart';
import 'package:ren/shared/widgets/skeleton.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';
import 'package:ren/shared/widgets/context_menu.dart';
import 'package:path_provider/path_provider.dart';

class ChatPage extends StatefulWidget {
  final ChatPreview chat;

  const ChatPage({super.key, required this.chat});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _PendingAttachment {
  final Uint8List bytes;
  final String filename;
  final String mimetype;

  const _PendingAttachment({
    required this.bytes,
    required this.filename,
    required this.mimetype,
  });
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  final List<ChatMessage> _messages = [];

  ChatMessage? _replyTo;
  ChatMessage? _editing;

  String? _pressedMessageId;

  bool _selectionMode = false;
  final Set<String> _selectedMessageIds = {};

  final _picker = ImagePicker();

  final List<_PendingAttachment> _pending = [];

  int? _myUserId;

  bool _peerOnline = false;
  bool _peerTyping = false;
  Timer? _typingDebounce;

  bool _isAtBottom = true;

  double _lastViewInsetsBottom = 0;

  RealtimeClient? _rt;
  StreamSubscription? _rtSub;

  String _messageSummary(ChatMessage m) {
    final t = m.text.trim();
    if (t.isNotEmpty) return t;
    if (m.attachments.isNotEmpty) {
      final a = m.attachments.first;
      if (a.isImage) return 'Фото';
      if (a.isVideo) return 'Видео';
      final name = a.filename.trim();
      return name.isNotEmpty ? name : 'Файл';
    }
    return '';
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
    for (final m in _messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
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
      _loadOlder();
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

    final pendingCopy = List<_PendingAttachment>.from(_pending);

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

      final added = <_PendingAttachment>[];
      for (final f in files) {
        final bytes = await f.readAsBytes();
        final name = f.name.isNotEmpty
            ? f.name
            : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        added.add(
          _PendingAttachment(
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
          _PendingAttachment(
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

      final added = <_PendingAttachment>[];
      for (final f in res.files) {
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final name = (f.name.isNotEmpty)
            ? f.name
            : 'file_${DateTime.now().millisecondsSinceEpoch}';
        final mime = lookupMimeType(f.path ?? '') ?? 'application/octet-stream';

        added.add(
          _PendingAttachment(
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

  Future<void> showAttachMenu(
    BuildContext context, {
    required Future<void> Function()? onPickPhotos,
    required Future<void> Function()? onPickFiles,
    required Future<void> Function()? onTakePhoto,
  }) async {
    final theme = Theme.of(context);

    await GlassOverlays.showGlassBottomSheet<void>(
      context,
      builder: (ctx) {
        return GlassSurface(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    height: 4,
                    width: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Title / optional subtitle
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Добавить',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Options row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _AttachOption(
                        icon: Icons.photo_library_outlined,
                        label: 'Фото',
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          HapticFeedback.selectionClick();
                          if (onPickPhotos != null) await onPickPhotos();
                        },
                      ),

                      _AttachOption(
                        icon: Icons.insert_drive_file_outlined,
                        label: 'Файл',
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          HapticFeedback.selectionClick();
                          if (onPickFiles != null) await onPickFiles();
                        },
                      ),

                      // Example: add a third quick action (camera)
                      _AttachOption(
                        icon: Icons.camera_alt_outlined,
                        label: 'Камера',
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          HapticFeedback.selectionClick();
                          if (onTakePhoto != null) await onTakePhoto();
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Optional explanatory text
                  Text(
                    'Выберите источник, чтобы прикрепить файл или фото',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  // Cancel button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Отмена'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  @override
  void dispose() {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    _typingDebounce?.cancel();
    _typingDebounce = null;
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
    final baseInk = isDark ? Colors.white : Colors.black;

    return AppBackground(
      imageOpacity: 1,
      imageBlurSigma: 0,
      imageFit: BoxFit.cover,
      animate: true,
      animationDuration: const Duration(seconds: 20),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: const GlassAppBarBackground(),
          centerTitle: true,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () {
              if (_selectionMode) {
                _exitSelectionMode();
              } else {
                Navigator.of(context).maybePop();
              }
            },
          ),
          title: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: double.infinity,
                child: Center(
                  child: GlassSurface(
                    borderRadius: 18,
                    blurSigma: 12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    borderColor: baseInk.withOpacity(isDark ? 0.18 : 0.10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectionMode)
                          Text(
                            'Выбрано: ${_selectedMessageIds.length}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          )
                        else ...[
                          RenAvatar(
                            url: widget.chat.user.avatarUrl,
                            name: widget.chat.user.name,
                            isOnline: _peerOnline,
                            size: 36,
                          ),
                          const SizedBox(width: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.chat.user.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _peerTyping
                                      ? 'Печатает...'
                                      : (_peerOnline ? 'Online' : 'Offline'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (_selectionMode) ...[
              IconButton(
                icon: Icon(
                  Icons.share_outlined,
                  color: theme.colorScheme.onSurface,
                ),
                onPressed: _selectedMessageIds.isEmpty
                    ? null
                    : () async {
                        await _forwardSelected();
                      },
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.onSurface,
                ),
                onPressed: _selectedMessageIds.isEmpty
                    ? null
                    : () {
                        final ids = Set<String>.from(_selectedMessageIds);
                        _deleteByIds(ids);
                        _deleteRemote(ids);
                      },
              ),
            ] else
              IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedMenu01,
                  color: theme.colorScheme.onSurface,
                  size: 24.0,
                ),
                onPressed: () {},
              ),
          ],
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

            Widget inputBar() {
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  horizontalPadding,
                  10,
                  horizontalPadding,
                  10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_editing != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassSurface(
                          borderRadius: 16,
                          blurSigma: 10,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Редактирование',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface.withOpacity(0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _editing = null;
                                  });
                                  _controller.clear();
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_replyTo != null)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeOut,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SizeTransition(
                              sizeFactor: animation,
                              axisAlignment: -1,
                              child: child,
                            ),
                          );
                        },
                        child: Padding(
                          key: ValueKey<String>('reply_${_replyTo!.id}'),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassSurface(
                            borderRadius: 16,
                            blurSigma: 12,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.reply,
                                  size: 16,
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _messageSummary(_replyTo!).isNotEmpty
                                        ? _messageSummary(_replyTo!)
                                        : 'Сообщение',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface.withOpacity(0.9),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _replyTo = null;
                                    });
                                  },
                                  child: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    if (_pending.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SizedBox(
                          height: 64,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _pending.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final p = _pending[index];
                              final isImg = p.mimetype.startsWith('image/');
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: 64,
                                      height: 64,
                                      color: theme.colorScheme.surface,
                                      child: isImg
                                          ? Image.memory(
                                              p.bytes,
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) => const SizedBox(),
                                            )
                                          : Center(
                                              child: Icon(
                                                Icons.insert_drive_file,
                                                color: theme.colorScheme.onSurface.withOpacity(0.65),
                                              ),
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    right: -6,
                                    top: -6,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _pending.removeAt(index);
                                        });
                                      },
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surface,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: theme.colorScheme.onSurface.withOpacity(0.25),
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: theme.colorScheme.onSurface.withOpacity(0.8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        GlassSurface(
                          borderRadius: 18,
                          blurSigma: 12,
                          width: inputHeight,
                          height: inputHeight,
                          onTap: () => showAttachMenu(
                            context,
                            onPickPhotos: () async => await _pickPhotos(),
                            onPickFiles: () async => await _pickFiles(),
                            onTakePhoto: () async => await _takePhoto(),
                          ),
                          child: Center(
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedAttachment01,
                              color: theme.colorScheme.onSurface.withOpacity(0.9),
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GlassSurface(
                            borderRadius: 18,
                            blurSigma: 12,
                            height: inputHeight,
                            borderColor: theme.colorScheme.onSurface
                                .withOpacity(isDark ? 0.20 : 0.10),
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 14,
                              ),
                              cursorColor: theme.colorScheme.primary,
                              decoration: InputDecoration(
                                hintText: 'Введите сообщение...',
                                hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.55),
                                ),
                                filled: false,
                                fillColor: Colors.transparent,
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GlassSurface(
                          borderRadius: 18,
                          blurSigma: 12,
                          width: inputHeight,
                          height: inputHeight,
                          onTap: _send,
                          child: Center(
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedSent,
                              color: theme.colorScheme.onSurface.withOpacity(0.9),
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }

            return Stack(
              children: [
                Positioned.fill(
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
                              alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
                              child: _SkeletonMessageBubble(isMe: alignRight),
                            );
                          },
                        )
                      : ListView.separated(
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
                                            child: _MessageBubble(
                                              replyPreview: (replyPreview != null && replyPreview.isNotEmpty)
                                                  ? replyPreview
                                                  : null,
                                              text: msg.text,
                                              attachments: msg.attachments,
                                              timeLabel: _formatTime(msg.sentAt),
                                              isMe: msg.isMe,
                                              isDark: isDark,
                                              onOpenAttachment: (a) => _openAttachmentSheet(a),
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
                      child: inputBar(),
                    ),
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
        return _AttachmentViewerSheet(
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

class _AttachmentViewerSheet extends StatefulWidget {
  final List<ChatAttachment> items;
  final int initialIndex;

  const _AttachmentViewerSheet({
    required this.items,
    required this.initialIndex,
  });

  @override
  State<_AttachmentViewerSheet> createState() => _AttachmentViewerSheetState();
}

class _AttachmentViewerSheetState extends State<_AttachmentViewerSheet> {
  late final PageController _pageController;
  int _index = 0;

  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, Future<void>> _videoInits = {};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    for (final c in _videoControllers.values) {
      c.dispose();
    }
    _videoControllers.clear();
    _videoInits.clear();
    _pageController.dispose();
    super.dispose();
  }

  ChatAttachment get _current => widget.items[_index];

  String _prettyType(ChatAttachment a) {
    final mt = a.mimetype.toLowerCase();
    if (mt.startsWith('image/')) return 'Фото';
    if (mt.startsWith('video/')) return 'Видео';
    if (mt.startsWith('audio/')) return 'Аудио';
    if (mt.contains('pdf')) return 'PDF';
    return 'Файл';
  }

  Future<void> _saveCurrent() async {
    final a = _current;
    final path = a.localPath;
    if (path.isEmpty) return;

    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = (box != null)
          ? (box.localToGlobal(Offset.zero) & box.size)
          : const Rect.fromLTWH(0, 0, 1, 1);

      await Share.shareXFiles(
        [XFile(path, name: a.filename)],
        text: a.filename,
        sharePositionOrigin: origin,
      );
    } catch (error) {
      if (!mounted) return;
      debugPrint('Failed to share file: $error');
      showGlassSnack(context, 'Не удалось сохранить файл', kind: GlassSnackKind.error);
    }
  }

  Future<void> _openCurrent() async {
    final a = _current;
    final path = a.localPath;
    if (path.isEmpty) return;
    try {
      await OpenFilex.open(path);
    } catch (_) {
      if (!mounted) return;
      showGlassSnack(context, 'Не удалось открыть файл', kind: GlassSnackKind.error);
    }
  }

  VideoPlayerController _getVideoController(int i, String path) {
    final existing = _videoControllers[i];
    if (existing != null) return existing;
    final c = VideoPlayerController.file(File(path));
    _videoControllers[i] = c;
    _videoInits[i] = c.initialize();
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.45,
      maxChildSize: 0.98,
      builder: (ctx, scrollController) {
        return GlassSurface(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _current.filename.isNotEmpty
                              ? _current.filename
                              : _prettyType(_current),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _saveCurrent,
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedDownload01,
                          color: theme.colorScheme.onSurface.withOpacity(0.9),
                          size: 18,
                        ),
                        label: const Text('Скачать'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (i) {
                      setState(() {
                        _index = i;
                      });
                    },
                    itemCount: widget.items.length,
                    itemBuilder: (context, i) {
                      final a = widget.items[i];
                      final path = a.localPath;

                      if (a.isImage) {
                        return Center(
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 4,
                            child: Image.file(
                              File(path),
                              errorBuilder: (context, error, stack) {
                                return const Text('Не удалось загрузить изображение');
                              },
                            ),
                          ),
                        );
                      }

                      if (a.isVideo) {
                        final c = _getVideoController(i, path);
                        final init = _videoInits[i];
                        return Center(
                          child: FutureBuilder<void>(
                            future: init,
                            builder: (context, snap) {
                              if (snap.connectionState != ConnectionState.done) {
                                return const CircularProgressIndicator();
                              }
                              if (!c.value.isInitialized) {
                                return const Text('Не удалось открыть видео');
                              }

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (c.value.isPlaying) {
                                      c.pause();
                                    } else {
                                      c.play();
                                    }
                                  });
                                },
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    AspectRatio(
                                      aspectRatio: c.value.aspectRatio,
                                      child: VideoPlayer(c),
                                    ),
                                    if (!c.value.isPlaying)
                                      Icon(
                                        Icons.play_circle_fill,
                                        size: 72,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      }

                      final icon = a.mimetype.startsWith('audio/')
                          ? Icons.audiotrack
                          : Icons.insert_drive_file;

                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icon,
                                size: 64,
                                color: theme.colorScheme.onSurface.withOpacity(0.75),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                a.filename.isNotEmpty ? a.filename : 'Файл',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _openCurrent,
                                    icon: const Icon(Icons.open_in_new),
                                    label: const Text('Открыть'),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton.icon(
                                    onPressed: _saveCurrent,
                                    icon: const Icon(Icons.download_outlined),
                                    label: const Text('Скачать'),
                                  ),
                                ],
                              ),
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
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String? replyPreview;
  final String text;
  final List<ChatAttachment> attachments;
  final String timeLabel;
  final bool isMe;
  final bool isDark;
  final void Function(ChatAttachment a)? onOpenAttachment;

  const _MessageBubble({
    this.replyPreview,
    required this.text,
    this.attachments = const [],
    required this.timeLabel,
    required this.isMe,
    required this.isDark,
    this.onOpenAttachment,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseInk = isDark ? Colors.white : Colors.black;
    final isMeColor = isMe
        ? (isDark
            ? theme.colorScheme.primary.withOpacity(0.35)
            : theme.colorScheme.primary.withOpacity(0.22))
        : null;

    void onTapAttachment(ChatAttachment a) {
      onOpenAttachment?.call(a);
    }

    return GlassSurface(
      borderRadius: 16,
      blurSigma: 12,
      color: isMeColor,
      borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (replyPreview != null && replyPreview!.trim().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.onSurface.withOpacity(0.08),
                    ),
                  ),
                  child: Text(
                    replyPreview!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.75),
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              for (final a in attachments) ...[
                if (a.isImage)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onTapAttachment(a),
                      borderRadius: BorderRadius.circular(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(a.localPath),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) {
                            return Container(
                              width: 220,
                              height: 160,
                              color: Theme.of(context).colorScheme.surface,
                            );
                          },
                        ),
                      ),
                    ),
                  )
                else if (a.isVideo)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onTapAttachment(a),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 220,
                        height: 140,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.onSurface.withOpacity(0.12),
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_circle_fill,
                                size: 48,
                                color: theme.colorScheme.onSurface.withOpacity(0.7),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                a.filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withOpacity(0.85),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onTapAttachment(a),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.insert_drive_file,
                              size: 16,
                              color: theme.colorScheme.onSurface.withOpacity(0.75),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                a.filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withOpacity(0.85),
                                  fontSize: 12,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
              ],
              Text(
                text,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                timeLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withOpacity(0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonMessageBubble extends StatelessWidget {
  final bool isMe;

  const _SkeletonMessageBubble({required this.isMe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxW = MediaQuery.of(context).size.width * 0.62;
    final w = isMe ? maxW : (maxW * 0.82);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: w),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            RenSkeletonBox(width: 180, height: 12, radius: 8),
            SizedBox(height: 8),
            RenSkeletonBox(width: 140, height: 12, radius: 8),
          ],
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AttachOption({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            width: 96,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                  child: Icon(icon, size: 28, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}