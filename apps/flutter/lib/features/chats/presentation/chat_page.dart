import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/shared/widgets/background.dart';
import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/theme/themes.dart';
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
  bool _loading = true;
  final List<ChatMessage> _messages = [];

  final _picker = ImagePicker();

  final List<_PendingAttachment> _pending = [];

  int? _myUserId;

  bool _peerOnline = false;
  bool _peerTyping = false;
  Timer? _typingDebounce;

  RealtimeClient? _rt;
  StreamSubscription? _rtSub;

  @override
  void initState() {
    super.initState();
    _peerOnline = widget.chat.user.isOnline;
    _controller.addListener(_onTextChanged);
    _init();
  }

  void _onTextChanged() {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    final rt = _rt;
    if (rt == null || !rt.isConnected) return;

    _typingDebounce?.cancel();

    final hasText = _controller.text.trim().isNotEmpty;
    rt.typing(chatId, hasText);

    _typingDebounce = Timer(const Duration(milliseconds: 900), () {
      final stillHas = _controller.text.trim().isNotEmpty;
      rt.typing(chatId, stillHas);
    });
  }

  Future<void> _init() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    final repo = context.read<ChatsRepository>();

    try {
      final list = await repo.fetchMessages(chatId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _loading = false;
      });
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
        final userId = evt.data['user_id'];
        if ('$userId' == '$peerId') {
          final status = (evt.data['status'] as String?) ?? '';
          final online = status == 'online';
          if (online != _peerOnline && mounted) {
            setState(() {
              _peerOnline = online;
            });
          }
        }
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

      final repo = context.read<ChatsRepository>();
      final decoded = await repo.decryptIncomingWsMessageFull(message: m);

      final senderId = m['sender_id'] is int
          ? m['sender_id'] as int
          : int.tryParse('${m['sender_id']}') ?? 0;
      final createdAtStr = (m['created_at'] as String?) ?? '';
      final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();

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
          ),
        );
      });
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

    final pendingCopy = List<_PendingAttachment>.from(_pending);
    setState(() {
      _pending.clear();
    });
    _controller.clear();

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
        ),
      );
    });

    final repo = context.read<ChatsRepository>();
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

    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;
    if (!rt.isConnected) {
      await rt.connect();
      rt.joinChat(chatId);
    }

    rt.sendMessage(
      chatId: chatId,
      message: payload['message'] as String,
      messageType: payload['message_type'] as String?,
      envelopes: payload['envelopes'] as Map<String, dynamic>?,
      metadata: payload['metadata'] as List<dynamic>?,
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
        final mime = (f.mimeType ?? '').isNotEmpty
            ? f.mimeType!
            : 'application/octet-stream';
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

  Future<void> _showAttachMenu() async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.95),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Фото'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _pickPhotos();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: const Text('Файл'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _pickFiles();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    _rt?.leaveChat(chatId);
    _rtSub?.cancel();
    _rtSub = null;
    _typingDebounce?.cancel();
    _typingDebounce = null;
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
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
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: const GlassAppBarBackground(),
          centerTitle: true,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
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
                        _Avatar(
                          url: widget.chat.user.avatarUrl,
                          name: widget.chat.user.name,
                          isOnline: widget.chat.user.isOnline,
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
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
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
            final double bottomInset = media.padding.bottom;

            final double listTopPadding = topInset + kToolbarHeight + 12;
            final double listBottomPadding =
                bottomInset + inputHeight + verticalPadding + 12;

            final messages = _messages;

            Widget inputBar() {
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  verticalPadding,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                          onTap: _showAttachMenu,
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
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.separated(
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
                            return Align(
                              alignment: msg.isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: _MessageBubble(
                                text: msg.text,
                                attachments: msg.attachments,
                                timeLabel: _formatTime(msg.sentAt),
                                isMe: msg.isMe,
                                isDark: isDark,
                              ),
                            );
                          },
                        ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: inputBar(),
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
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final List<ChatAttachment> attachments;
  final String timeLabel;
  final bool isMe;
  final bool isDark;

  const _MessageBubble({
    required this.text,
    this.attachments = const [],
    required this.timeLabel,
    required this.isMe,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseInk = isDark ? Colors.white : Colors.black;
    final isMeColor = isMe
        ? (isDark
            ? AppColors.primary.withOpacity(0.35)
            : AppColors.primary.withOpacity(0.22))
        : null;

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
              for (final a in attachments) ...[
                if (a.isImage)
                  ClipRRect(
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
                  )
                else
                  Text(
                    a.filename,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.85),
                      fontSize: 12,
                      height: 1.25,
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

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final bool isOnline;
  final double size;

  const _Avatar({
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
                    width: size,
                    height: size,
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
                        width: size,
                        height: size,
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
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isOnline ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black.withOpacity(0.25), width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
