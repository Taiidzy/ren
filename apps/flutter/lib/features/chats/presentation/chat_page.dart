import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:ren/features/chats/data/fake_chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/shared/widgets/background.dart';
import 'package:ren/theme/themes.dart';

class ChatPage extends StatefulWidget {
  final ChatPreview chat;

  const ChatPage({super.key, required this.chat});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _repo = const FakeChatsRepository();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final messages = _repo.messages(widget.chat.id);

    return AppBackground(
      imageOpacity: 1,
      imageBlurSigma: 0,
      imageFit: BoxFit.cover,
      showGradient: true,
      gradientOpacity: 1,
      animate: true,
      animationDuration: const Duration(seconds: 20),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.matteGlass,
          elevation: 0,
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Avatar(
                      url: widget.chat.user.avatarUrl,
                      isOnline: widget.chat.user.isOnline,
                      size: 36,
                    ),
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            widget.chat.user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.chat.user.isOnline ? 'Online' : 'Offline',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  itemCount: messages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return Align(
                      alignment:
                          msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Material(
                          color: AppColors.matteGlass,
                          child: InkWell(
                            onTap: () {},
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: HugeIcon(
                                  icon: HugeIcons.strokeRoundedAttachment01,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.9),
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.matteGlass,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withOpacity(isDark ? 0.20 : 0.10),
                              ),
                            ),
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
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Material(
                          color: AppColors.matteGlass,
                          child: InkWell(
                            onTap: () {},
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: HugeIcon(
                                  icon: HugeIcons.strokeRoundedSent,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.9),
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            color: AppColors.matteGlass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: baseInk.withOpacity(isDark ? 0.20 : 0.10)),
          ),
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
  final bool isOnline;
  final double size;

  const _Avatar({required this.url, required this.isOnline, required this.size});

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
