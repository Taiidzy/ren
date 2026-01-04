import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/shared/widgets/background.dart';
import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/theme/themes.dart';

class ChatPage extends StatefulWidget {
  final ChatPreview chat;

  const ChatPage({super.key, required this.chat});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  bool _loading = true;
  final List<ChatMessage> _messages = [];

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
          : Map<String, dynamic>.from(msg as Map);
      final repo = context.read<ChatsRepository>();
      final text = await repo.decryptIncomingWsMessage(message: m);

      final senderId = m['sender_id'] is int
          ? m['sender_id'] as int
          : int.tryParse('${m['sender_id']}') ?? 0;
      final createdAtStr = (m['created_at'] as String?) ?? '';
      final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();

      final myId = _myUserId ?? 0;
      final isMe = (myId > 0) ? senderId == myId : senderId != peerId;

      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            id: '${m['id'] ?? DateTime.now().millisecondsSinceEpoch}',
            chatId: chatId.toString(),
            isMe: isMe,
            text: text,
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
    if (text.isEmpty) return;
    if (peerId <= 0) return;

    _controller.clear();

    // optimistic
    setState(() {
      _messages.add(
        ChatMessage(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
          chatId: chatId.toString(),
          isMe: true,
          text: text,
          sentAt: DateTime.now(),
        ),
      );
    });

    final repo = context.read<ChatsRepository>();
    final payload = await repo.buildEncryptedWsMessage(
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
                child: Row(
                  children: [
                    GlassSurface(
                      borderRadius: 18,
                      blurSigma: 12,
                      width: inputHeight,
                      height: inputHeight,
                      onTap: () {},
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
  final String timeLabel;
  final bool isMe;
  final bool isDark;

  const _MessageBubble({
    required this.text,
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
