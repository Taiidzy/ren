import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:ren/features/chats/presentation/widgets/chat_attach_menu.dart';
import 'package:ren/features/chats/presentation/widgets/chat_pending_attachment.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  final bool isDark;

  final bool isEditing;
  final VoidCallback onCancelEditing;

  final bool hasReply;
  final String replyText;
  final VoidCallback onCancelReply;

  final List<PendingChatAttachment> pending;
  final void Function(int index) onRemovePending;

  final Future<void> Function() onPickPhotos;
  final Future<void> Function() onPickFiles;
  final Future<void> Function() onTakePhoto;

  final VoidCallback onSend;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.isEditing,
    required this.onCancelEditing,
    required this.hasReply,
    required this.replyText,
    required this.onCancelReply,
    required this.pending,
    required this.onRemovePending,
    required this.onPickPhotos,
    required this.onPickFiles,
    required this.onTakePhoto,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const double inputHeight = 44;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEditing)
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
                      onTap: onCancelEditing,
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
          if (hasReply)
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
                key: ValueKey<String>('reply_${replyText.trim()}'),
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
                          replyText.trim().isNotEmpty ? replyText.trim() : 'Сообщение',
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
                        onTap: onCancelReply,
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
          if (pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: pending.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final p = pending[index];
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
                            onTap: () => onRemovePending(index),
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
                onTap: () => showChatAttachMenu(
                  context,
                  onPickPhotos: () async => await onPickPhotos(),
                  onPickFiles: () async => await onPickFiles(),
                  onTakePhoto: () async => await onTakePhoto(),
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
                  borderColor: theme.colorScheme.onSurface.withOpacity(isDark ? 0.20 : 0.10),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                    ),
                    cursorColor: theme.colorScheme.primary,
                    decoration: InputDecoration(
                      hintText: 'Введите сообщение...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                      ),
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
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
                onTap: onSend,
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
}
