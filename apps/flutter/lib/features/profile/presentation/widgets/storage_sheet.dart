import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ren/core/cache/chats_local_cache.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class StorageSheet {
  static Future<void> show(BuildContext context) async {
    await GlassOverlays.showGlassBottomSheet<void>(
      context,
      builder: (_) => const _StorageSheetBody(),
    );
  }
}

class _StorageSheetBody extends StatefulWidget {
  const _StorageSheetBody();

  @override
  State<_StorageSheetBody> createState() => _StorageSheetBodyState();
}

class _StorageSheetBodyState extends State<_StorageSheetBody> {
  bool _loading = true;
  bool _clearing = false;
  bool _savingLimit = false;
  bool _showPostClearHint = false;
  bool _clearChats = true;
  bool _clearMessages = true;
  bool _clearMedia = true;
  int _limitBytes = ChatsLocalCache.defaultCacheLimitBytes;
  double _limitGb = 1;
  CacheUsageStats _usage = const CacheUsageStats(
    chatsBytes: 0,
    messagesBytes: 0,
    mediaBytes: 0,
  );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = context.read<ChatsRepository>();
    final usage = await repo.getCacheUsageStats();
    final limit = await repo.getCacheLimitBytes();
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _limitBytes = limit;
      _limitGb = (limit / (1024 * 1024 * 1024)).clamp(1, 50).toDouble();
      _loading = false;
    });
  }

  String _fmt(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var idx = 0;
    while (size >= 1024 && idx < units.length - 1) {
      size /= 1024;
      idx++;
    }
    return '${size.toStringAsFixed(idx == 0 ? 0 : 1)} ${units[idx]}';
  }

  Widget _segment({
    required Color color,
    required int value,
    required int total,
    required String label,
  }) {
    final share = total <= 0 ? 0.0 : value / total;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Flexible(
          child: Text(
            '${(share * 100).toStringAsFixed(1)}% • ${_fmt(value)}',
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Future<void> _saveLimit() async {
    final nextBytes = (_limitGb * 1024 * 1024 * 1024).round();
    final clamped = nextBytes.clamp(
      ChatsLocalCache.minCacheLimitBytes,
      ChatsLocalCache.maxCacheLimitBytes,
    );
    if (clamped == _limitBytes) return;
    setState(() {
      _savingLimit = true;
    });
    try {
      await context.read<ChatsRepository>().setCacheLimitBytes(clamped);
      if (!mounted) return;
      setState(() {
        _limitBytes = clamped;
      });
      showGlassSnack(
        context,
        'Лимит кэша обновлён: ${_limitGb.toStringAsFixed(0)} ГБ',
        kind: GlassSnackKind.success,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(
        context,
        'Не удалось обновить лимит: $e',
        kind: GlassSnackKind.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingLimit = false;
        });
      }
    }
  }

  Future<void> _clearSelected() async {
    if (!_clearChats && !_clearMessages && !_clearMedia) {
      showGlassSnack(
        context,
        'Выберите хотя бы один тип данных',
        kind: GlassSnackKind.info,
      );
      return;
    }
    setState(() {
      _clearing = true;
    });
    try {
      await context.read<ChatsRepository>().clearAppCache(
        includeChats: _clearChats,
        includeMessages: _clearMessages,
        includeMedia: _clearMedia,
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      setState(() {
        _showPostClearHint = true;
      });
      showGlassSnack(
        context,
        'Кэш очищен. Данные будут загружены заново при синхронизации.',
        kind: GlassSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(
        context,
        'Не удалось очистить кэш: $e',
        kind: GlassSnackKind.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _clearing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;
    final sheetWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = sheetWidth < 360 ? 12.0 : 16.0;
    final bottomPadding = sheetWidth < 360 ? 14.0 : 16.0;

    final total = _usage.totalBytes;
    final cap = _limitBytes <= 0
        ? ChatsLocalCache.defaultCacheLimitBytes
        : _limitBytes;
    final usedRatio = (total / cap).clamp(0.0, 1.0);

    final chatsColor = const Color(0xFF3B82F6);
    final messagesColor = const Color(0xFF10B981);
    final mediaColor = const Color(0xFFF59E0B);

    int flexFor(int value) {
      if (total <= 0) return 1;
      final f = (value / total * 1000).round();
      return f < 1 ? 1 : f;
    }

    return GlassSurface(
      blurSigma: 16,
      borderRadiusGeometry: const BorderRadius.only(
        topLeft: Radius.circular(26),
        topRight: Radius.circular(26),
      ),
      borderColor: baseInk.withOpacity(isDark ? 0.22 : 0.12),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            bottomPadding,
          ),
          child: _loading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.25,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Хранилище',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Использовано ${_fmt(total)} из ${_fmt(cap)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.75),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          height: 10,
                          color: theme.colorScheme.onSurface.withOpacity(0.10),
                          child: total == 0
                              ? const SizedBox.shrink()
                              : Row(
                                  children: [
                                    Flexible(
                                      flex: flexFor(_usage.chatsBytes),
                                      child: Container(color: chatsColor),
                                    ),
                                    Flexible(
                                      flex: flexFor(_usage.messagesBytes),
                                      child: Container(color: messagesColor),
                                    ),
                                    Flexible(
                                      flex: flexFor(_usage.mediaBytes),
                                      child: Container(color: mediaColor),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: usedRatio,
                        minHeight: 4,
                        backgroundColor: theme.colorScheme.onSurface
                            .withOpacity(0.10),
                      ),
                      const SizedBox(height: 14),
                      _segment(
                        color: chatsColor,
                        value: _usage.chatsBytes,
                        total: total,
                        label: 'Список чатов',
                      ),
                      const SizedBox(height: 8),
                      _segment(
                        color: messagesColor,
                        value: _usage.messagesBytes,
                        total: total,
                        label: 'Сообщения',
                      ),
                      const SizedBox(height: 8),
                      _segment(
                        color: mediaColor,
                        value: _usage.mediaBytes,
                        total: total,
                        label: 'Медиа',
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Лимит кэша: ${_limitGb.toStringAsFixed(0)} ГБ',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Slider(
                        value: _limitGb,
                        min: 1,
                        max: 50,
                        divisions: 49,
                        label: '${_limitGb.toStringAsFixed(0)} ГБ',
                        onChanged: (_savingLimit || _clearing)
                            ? null
                            : (value) {
                                setState(() {
                                  _limitGb = value.roundToDouble();
                                });
                              },
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 42),
                        child: GlassSurface(
                          borderRadius: 12,
                          blurSigma: 10,
                          onTap: (_savingLimit || _clearing)
                              ? null
                              : _saveLimit,
                          child: Center(
                            child: _savingLimit
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Применить лимит',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Очистить список чатов'),
                        value: _clearChats,
                        onChanged: _clearing
                            ? null
                            : (v) {
                                setState(() {
                                  _clearChats = v;
                                });
                              },
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Очистить сообщения'),
                        value: _clearMessages,
                        onChanged: _clearing
                            ? null
                            : (v) {
                                setState(() {
                                  _clearMessages = v;
                                });
                              },
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Очистить медиа'),
                        value: _clearMedia,
                        onChanged: _clearing
                            ? null
                            : (v) {
                                setState(() {
                                  _clearMedia = v;
                                });
                              },
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 46),
                        child: GlassSurface(
                          borderRadius: 14,
                          blurSigma: 12,
                          color: const Color(0xFF991B1B).withOpacity(0.55),
                          onTap: _clearing ? null : _clearSelected,
                          child: Center(
                            child: _clearing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Очистить выбранное',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      if (_showPostClearHint) ...[
                        const SizedBox(height: 10),
                        Text(
                          'После очистки список чатов и сообщения подгрузятся при следующей синхронизации.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.72,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
