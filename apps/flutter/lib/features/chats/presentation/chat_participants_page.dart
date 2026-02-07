import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/core/realtime/realtime_client.dart';

import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ChatParticipantsPage extends StatefulWidget {
  final ChatPreview chat;

  const ChatParticipantsPage({
    super.key,
    required this.chat,
  });

  @override
  State<ChatParticipantsPage> createState() => _ChatParticipantsPageState();
}

class _ChatParticipantsPageState extends State<ChatParticipantsPage> {
  bool _loading = true;
  String? _error;
  List<_ParticipantVm> _participants = const [];

  int? _myId;
  bool _isAdmin = false;

  bool _rotationRequired = false;

  RealtimeClient? _rt;
  StreamSubscription? _rtSub;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    unawaited(_ensureRealtime());
  }

  @override
  void dispose() {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    _rtSub?.cancel();
    _rtSub = null;
    _rt?.leaveChat(chatId);
    super.dispose();
  }

  Future<void> _ensureRealtime() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;
    if (!rt.isConnected) {
      await rt.connect();
    }
    rt.joinChat(chatId);

    _rtSub ??= rt.events.listen((evt) async {
      if (evt.type != 'participants_changed' && evt.type != 'chat_key_rotated') {
        return;
      }

      final evtChatId = evt.data['chat_id'] ?? evt.data['chatId'];
      if ('$evtChatId' != '$chatId') return;

      final rot = evt.data['rotation_required'];
      final rotationRequired = rot == true || rot == 1 || rot == '1' || rot == 'true';

      if (!mounted) return;
      if (evt.type == 'participants_changed') {
        setState(() {
          _rotationRequired = rotationRequired;
        });
        await _reload();
        return;
      }

      if (evt.type == 'chat_key_rotated') {
        setState(() {
          _rotationRequired = false;
        });
        await _reload();
        return;
      }
    });
  }

  Future<void> _reload() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<ChatsRepository>();
      final list = await repo.api.getParticipants(chatId);

      final myIdStr = await SecureStorage.readKey(Keys.UserId);
      final myId = int.tryParse(myIdStr ?? '') ?? 0;
      _myId = myId > 0 ? myId : null;

      final out = <_ParticipantVm>[];
      for (final it in list) {
        final parsed = _ParticipantVm.tryParse(it);
        if (parsed != null) out.add(parsed);
      }

      final myVm = (_myId == null)
          ? null
          : out.cast<_ParticipantVm?>().firstWhere(
                (p) => p != null && p.userId == _myId,
                orElse: () => null,
              );
      final isAdmin = myVm?.role == 'admin';

      out.sort((a, b) {
        if (_myId != null && a.userId == _myId && b.userId != _myId) return -1;
        if (_myId != null && b.userId == _myId && a.userId != _myId) return 1;
        return a.userId.compareTo(b.userId);
      });

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _participants = out;
        _isAdmin = isAdmin;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _participants = const [];
        _isAdmin = false;
      });
    }
  }

  Future<void> _addParticipantFlow() async {
    if (!mounted) return;

    final selected = await GlassOverlays.showGlassBottomSheet<ChatUser>(
      context,
      builder: (ctx) => _AddParticipantSheet(chatId: widget.chat.id),
    );

    if (!mounted) return;
    if (selected == null) return;

    final uid = int.tryParse(selected.id) ?? 0;
    if (uid <= 0) return;

    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    try {
      final repo = context.read<ChatsRepository>();
      await repo.api.addParticipant(chatId, uid);

      repo.invalidateChatKey(chatId);
      await repo.prefetchLatestChatKey(chatId);

      if (!mounted) return;
      showGlassSnack(context, 'Участник добавлен', kind: GlassSnackKind.success);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, e.toString(), kind: GlassSnackKind.error);
    }
  }

  Future<void> _removeParticipant(int userId) async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0 || userId <= 0) return;

    final repo = context.read<ChatsRepository>();

    final ok = await GlassOverlays.showGlassDialog<bool>(
      context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Удалить участника?'),
          content: Text('User ID: $userId'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await repo.api.removeParticipant(chatId, userId);

      repo.invalidateChatKey(chatId);
      await repo.prefetchLatestChatKey(chatId);

      if (!mounted) return;
      showGlassSnack(context, 'Участник удалён', kind: GlassSnackKind.success);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, e.toString(), kind: GlassSnackKind.error);
    }
  }

  Future<void> _leaveChat() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    final repo = context.read<ChatsRepository>();

    final ok = await GlassOverlays.showGlassDialog<bool>(
      context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Выйти из чата?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Выйти'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await repo.api.leaveChat(chatId);

      if (!mounted) return;
      showGlassSnack(context, 'Вы вышли из чата', kind: GlassSnackKind.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, e.toString(), kind: GlassSnackKind.error);
    }
  }

  Future<void> _rotateKey() async {
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    final repo = context.read<ChatsRepository>();

    final ok = await GlassOverlays.showGlassDialog<bool>(
      context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Ротация ключа?'),
          content: const Text('Ключ будет обновлён для всех участников.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ротировать'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await repo.rotateChatKey(chatId);
      if (!mounted) return;
      showGlassSnack(context, 'Ключ обновлён', kind: GlassSnackKind.success);
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, e.toString(), kind: GlassSnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isGroupOrChannel = widget.chat.kind == 'group' || widget.chat.kind == 'channel';
    final isChannel = widget.chat.kind == 'channel';
    final showRotationBanner = isGroupOrChannel && _rotationRequired;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Участники'),
        actions: [
          IconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedRefresh,
              color: theme.colorScheme.onSurface,
              size: 22,
            ),
            onPressed: _loading ? null : _reload,
          ),
          if (isGroupOrChannel)
            IconButton(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedAdd01,
                color: theme.colorScheme.onSurface,
                size: 22,
              ),
              onPressed: _isAdmin ? _addParticipantFlow : null,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: GlassSurface(
                    borderRadius: 18,
                    blurSigma: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedInformationCircle,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Chat ID: ${widget.chat.id}  •  ${widget.chat.kind}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.75),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isChannel)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassSurface(
                  borderRadius: 18,
                  blurSigma: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedMegaphone01,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Канал: публиковать могут только админы',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (showRotationBanner)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassSurface(
                  borderRadius: 18,
                  blurSigma: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedKey01,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _isAdmin
                              ? 'Требуется ротация ключа'
                              : 'Требуется ротация ключа (нужен admin)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_isAdmin)
                        TextButton(
                          onPressed: _rotateKey,
                          child: const Text('Rotate'),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_error != null)
                      ? Center(
                          child: Text(
                            _error ?? '',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _participants.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final p = _participants[index];
                            final isMe = _myId != null && p.userId == _myId;

                            return GlassSurface(
                              borderRadius: 18,
                              blurSigma: 14,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
                                    backgroundImage: (p.avatarUrl.isNotEmpty)
                                        ? NetworkImage(p.avatarUrl)
                                        : null,
                                    child: (p.avatarUrl.isEmpty)
                                        ? Text(
                                            p.title.isNotEmpty ? p.title[0].toUpperCase() : '?',
                                            style: TextStyle(
                                              color: theme.colorScheme.onSurface,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                p.title + (isMe ? ' (you)' : ''),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: theme.colorScheme.onSurface,
                                                ),
                                              ),
                                            ),
                                            if (p.role == 'admin')
                                              Container(
                                                margin: const EdgeInsets.only(left: 8),
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: theme.colorScheme.primary.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(999),
                                                  border: Border.all(
                                                    color: theme.colorScheme.primary.withOpacity(0.35),
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Text(
                                                  'ADMIN',
                                                  style: theme.textTheme.labelSmall?.copyWith(
                                                    letterSpacing: 0.4,
                                                    fontWeight: FontWeight.w800,
                                                    color: theme.colorScheme.primary,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'ID: ${p.userId}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (isGroupOrChannel && _isAdmin && !isMe)
                                    IconButton(
                                      icon: HugeIcon(
                                        icon: HugeIcons.strokeRoundedRemoveCircle,
                                        color: theme.colorScheme.error,
                                        size: 22,
                                      ),
                                      onPressed: () => _removeParticipant(p.userId),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 12),
            if (isGroupOrChannel && _isAdmin)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _rotateKey,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedKey01),
                      label: const Text('Rotate key'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _leaveChat,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedLogout03),
                      label: const Text('Выйти'),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _leaveChat,
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedLogout03),
                  label: const Text('Выйти'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantVm {
  final int userId;
  final String title;
  final String avatarUrl;
  final String role;

  const _ParticipantVm({
    required this.userId,
    required this.title,
    required this.avatarUrl,
    required this.role,
  });

  static _ParticipantVm? tryParse(dynamic raw) {
    if (raw is int) {
      return _ParticipantVm(userId: raw, title: 'User', avatarUrl: '', role: 'member');
    }
    if (raw is! Map) return null;

    final dynId = raw['user_id'] ?? raw['userId'] ?? raw['id'];
    final userId = (dynId is int) ? dynId : int.tryParse('${dynId ?? ''}') ?? 0;
    if (userId <= 0) return null;

    final name = (raw['username'] ?? raw['name'] ?? raw['title'] ?? 'User').toString();
    final avatar = (raw['avatar'] ?? raw['avatar_url'] ?? raw['avatarUrl'] ?? '').toString();
    final role = (raw['role'] ?? 'member').toString().trim().toLowerCase();

    return _ParticipantVm(
      userId: userId,
      title: name.trim().isNotEmpty ? name.trim() : 'User',
      avatarUrl: avatar.trim(),
      role: role.isNotEmpty ? role : 'member',
    );
  }
}

class _AddParticipantSheet extends StatefulWidget {
  final String chatId;

  const _AddParticipantSheet({
    required this.chatId,
  });

  @override
  State<_AddParticipantSheet> createState() => _AddParticipantSheetState();
}

class _AddParticipantSheetState extends State<_AddParticipantSheet> {
  final _controller = TextEditingController();

  bool _loading = false;
  String? _error;
  List<ChatUser> _users = const [];

  int _seq = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _debounce = null;
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  void _run() {
    final q = _controller.text.trim();
    final seq = ++_seq;

    if (q.isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _users = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final repo = context.read<ChatsRepository>();
    repo.searchUsers(q).then((list) {
      if (!mounted) return;
      if (seq != _seq) return;
      setState(() {
        _loading = false;
        _error = null;
        _users = list;
      });
    }).catchError((e) {
      if (!mounted) return;
      if (seq != _seq) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _users = const [];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassSurface(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Добавить участника',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                onChanged: (_) => _onChanged(),
                decoration: const InputDecoration(
                  hintText: 'Поиск пользователей...',
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    _error ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                )
              else if (_users.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Ничего не найдено',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final u = _users[index];
                      return GlassSurface(
                        borderRadius: 18,
                        blurSigma: 14,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(u),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
                                backgroundImage:
                                    (u.avatarUrl.isNotEmpty) ? NetworkImage(u.avatarUrl) : null,
                                child: (u.avatarUrl.isEmpty)
                                    ? Text(
                                        u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      u.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ID: ${u.id}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedAdd01,
                                color: theme.colorScheme.onSurface.withOpacity(0.65),
                                size: 18.0,
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
      ),
    );
  }
}
