import 'dart:io';

import 'package:flutter/material.dart';

import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ChatMessageBubble extends StatelessWidget {
  final String? replyPreview;
  final String text;
  final List<ChatAttachment> attachments;
  final String timeLabel;
  final bool isMe;
  final bool isDark;
  final void Function(ChatAttachment a)? onOpenAttachment;

  const ChatMessageBubble({
    super.key,
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
    final dpr = MediaQuery.of(context).devicePixelRatio;
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
                        child: RepaintBoundary(
                          child: Image.file(
                            File(a.localPath),
                            fit: BoxFit.cover,
                            cacheWidth: (220 * dpr).round(),
                            cacheHeight: (160 * dpr).round(),
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
