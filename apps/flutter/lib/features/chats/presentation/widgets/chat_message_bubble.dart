import 'dart:io';
import 'dart:ui' as ui;

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

    final images = <ChatAttachment>[];
    final otherAttachments = <ChatAttachment>[];
    for (final a in attachments) {
      if (a.isImage) {
        images.add(a);
      } else {
        otherAttachments.add(a);
      }
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
              if (images.isNotEmpty) ...[
                _ChatImageGroup(
                  images: images,
                  dpr: dpr,
                  onTap: onTapAttachment,
                ),
                const SizedBox(height: 6),
              ],
              for (final a in otherAttachments) ...[
                if (a.isVideo)
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

class _ChatImageGroup extends StatelessWidget {
  final List<ChatAttachment> images;
  final double dpr;
  final void Function(ChatAttachment a) onTap;

  const _ChatImageGroup({
    required this.images,
    required this.dpr,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (images.length <= 4) {
      return _ChatImageCollage(
        images: images,
        dpr: dpr,
        onTap: onTap,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in images) ...[
          _ChatImageThumb(
            attachment: a,
            dpr: dpr,
            single: false,
            onTap: onTap,
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _ChatImageCollage extends StatelessWidget {
  final List<ChatAttachment> images;
  final double dpr;
  final void Function(ChatAttachment a) onTap;

  const _ChatImageCollage({
    required this.images,
    required this.dpr,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const gap = 2.0;

    Future<List<double?>> readAll() async {
      final out = <double?>[];
      for (final a in images) {
        out.add(await _ChatImageAspectCache.instance.read(a.localPath));
      }
      return out;
    }

    return FutureBuilder<List<double?>>(
      future: readAll(),
      builder: (context, snap) {
        final ars = snap.data;

        bool isLandscape(int i) {
          final ar = (ars != null && i < ars.length) ? ars[i] : null;
          if (ar == null || !ar.isFinite) return false;
          return ar > 1.20;
        }

        if (images.length == 1) {
          return _ChatImageThumb(
            attachment: images[0],
            dpr: dpr,
            single: true,
            onTap: onTap,
          );
        }

        if (images.length == 2) {
          final aLand = isLandscape(0);
          final bLand = isLandscape(1);
          final stack = aLand && bLand;

          if (stack) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChatImageThumb(
                  attachment: images[0],
                  dpr: dpr,
                  single: false,
                  onTap: onTap,
                ),
                const SizedBox(height: 6),
                _ChatImageThumb(
                  attachment: images[1],
                  dpr: dpr,
                  single: false,
                  onTap: onTap,
                ),
              ],
            );
          }

          return SizedBox(
            width: 220,
            child: Row(
              children: [
                Expanded(
                  child: _ChatImageThumb(
                    attachment: images[0],
                    dpr: dpr,
                    single: false,
                    tight: true,
                    onTap: onTap,
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: _ChatImageThumb(
                    attachment: images[1],
                    dpr: dpr,
                    single: false,
                    tight: true,
                    onTap: onTap,
                  ),
                ),
              ],
            ),
          );
        }

        if (images.length == 3) {
          final land0 = isLandscape(0);
          final land1 = isLandscape(1);
          final land2 = isLandscape(2);
          final hasLandscape = land0 || land1 || land2;

          if (hasLandscape) {
            int topIndex = 0;
            if (land1 && !land0) topIndex = 1;
            if (land2 && !(land0 || land1)) topIndex = 2;

            final other = <ChatAttachment>[];
            for (int i = 0; i < images.length; i++) {
              if (i == topIndex) continue;
              other.add(images[i]);
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChatImageThumb(
                  attachment: images[topIndex],
                  dpr: dpr,
                  single: false,
                  onTap: onTap,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: _ChatImageThumb(
                        attachment: other[0],
                        dpr: dpr,
                        single: false,
                        tight: true,
                        onTap: onTap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ChatImageThumb(
                        attachment: other[1],
                        dpr: dpr,
                        single: false,
                        tight: true,
                        onTap: onTap,
                      ),
                    ),
                  ],
                ),
              ],
            );
          }

          return SizedBox(
            width: 220,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _ChatImageThumb(
                    attachment: images[0],
                    dpr: dpr,
                    single: false,
                    tight: true,
                    onTap: onTap,
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Expanded(
                        child: _ChatImageThumb(
                          attachment: images[1],
                          dpr: dpr,
                          single: false,
                          tight: true,
                          onTap: onTap,
                        ),
                      ),
                      const SizedBox(height: gap),
                      Expanded(
                        child: _ChatImageThumb(
                          attachment: images[2],
                          dpr: dpr,
                          single: false,
                          tight: true,
                          onTap: onTap,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return SizedBox(
          width: 220,
          height: 220,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _ChatImageThumb(
                        attachment: images[0],
                        dpr: dpr,
                        single: false,
                        tight: true,
                        onTap: onTap,
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      child: _ChatImageThumb(
                        attachment: images[1],
                        dpr: dpr,
                        single: false,
                        tight: true,
                        onTap: onTap,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: gap),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _ChatImageThumb(
                        attachment: images[2],
                        dpr: dpr,
                        single: false,
                        tight: true,
                        onTap: onTap,
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      child: _ChatImageThumb(
                        attachment: images[3],
                        dpr: dpr,
                        single: false,
                        tight: true,
                        onTap: onTap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatImageThumb extends StatelessWidget {
  final ChatAttachment attachment;
  final double dpr;
  final bool single;
  final bool tight;
  final void Function(ChatAttachment a) onTap;

  const _ChatImageThumb({
    required this.attachment,
    required this.dpr,
    required this.single,
    required this.onTap,
    this.tight = false,
  });

  @override
  Widget build(BuildContext context) {
    final maxW = tight ? double.infinity : 220.0;

    return FutureBuilder<double?>(
      future: _ChatImageAspectCache.instance.read(attachment.localPath),
      builder: (context, snap) {
        final ar = snap.data;
        final isTall = (ar != null) ? (ar < 0.75) : false;

        final fit = (single && isTall) ? BoxFit.contain : BoxFit.cover;
        final maxH = (single && isTall) ? 360.0 : (tight ? 180.0 : 160.0);

        Widget content = Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onTap(attachment),
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxW,
                  maxHeight: maxH,
                ),
                child: RepaintBoundary(
                  child: Image.file(
                    File(attachment.localPath),
                    fit: fit,
                    cacheWidth: (220 * dpr).round(),
                    cacheHeight: (maxH * dpr).round(),
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
          ),
        );

        return content;
      },
    );
  }
}

class _ChatImageAspectCache {
  _ChatImageAspectCache._();

  static final _ChatImageAspectCache instance = _ChatImageAspectCache._();

  final Map<String, Future<double?>> _cache = <String, Future<double?>>{};

  Future<double?> read(String path) {
    return _cache.putIfAbsent(path, () async {
      try {
        final bytes = await File(path).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final img = frame.image;
        final w = img.width.toDouble();
        final h = img.height.toDouble();
        img.dispose();
        return (h == 0) ? null : (w / h);
      } catch (_) {
        return null;
      }
    });
  }

  Future<({double arA, double arB})> readPair(String a, String b) async {
    final ra = await read(a);
    final rb = await read(b);
    return (arA: ra ?? 1.0, arB: rb ?? 1.0);
  }
}
