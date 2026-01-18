import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ChatAttachmentViewerSheet extends StatefulWidget {
  final List<ChatAttachment> items;
  final int initialIndex;

  const ChatAttachmentViewerSheet({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<ChatAttachmentViewerSheet> createState() => _ChatAttachmentViewerSheetState();
}

class _ChatAttachmentViewerSheetState extends State<ChatAttachmentViewerSheet> {
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
                          _current.filename.isNotEmpty ? _current.filename : _prettyType(_current),
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
