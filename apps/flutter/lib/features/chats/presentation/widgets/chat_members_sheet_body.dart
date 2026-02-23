import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/shared/widgets/avatar.dart';
import 'package:ren/shared/widgets/context_menu.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ChatMembersSheetBody extends StatefulWidget {
  final int chatId;
  final String chatKind;
  final int myUserId;
  final ChatsRepository repo;

  const ChatMembersSheetBody({
    super.key,
    required this.chatId,
    required this.chatKind,
    required this.myUserId,
    required this.repo,
  });

  @override
  State<ChatMembersSheetBody> createState() => _ChatMembersSheetBodyState();
}

class _ChatMembersSheetBodyState extends State<ChatMembersSheetBody> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<ChatMember> _members = const [];
  RealtimeClient? _rt;
  StreamSubscription? _rtSub;
  Timer? _realtimeReloadDebounce;

  final TextEditingController _memberIdCtrl = TextEditingController();
  final TextEditingController _memberSearchCtrl = TextEditingController();
  final String _newMemberRole = 'member';
  Timer? _memberSearchDebounce;
  int _memberSearchSeq = 0;
  bool _memberSearching = false;
  String? _memberSearchError;
  List<ChatUser> _memberSearchResults = const [];

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }

  bool get _canManage {
    final me = _members
        .where((m) => m.userId == widget.myUserId)
        .cast<ChatMember?>()
        .firstWhere((m) => m != null, orElse: () => null);
    if (me == null) return false;
    final role = me.role.trim().toLowerCase();
    return role == 'owner' || role == 'admin';
  }

  @override
  void initState() {
    super.initState();
    _reload();
    _ensureRealtime();
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _realtimeReloadDebounce?.cancel();
    _memberSearchDebounce?.cancel();
    _memberSearchCtrl.dispose();
    _memberIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload({bool withLoading = true}) async {
    if (!mounted) return;
    if (withLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final members = await widget.repo.listMembers(widget.chatId);
      if (!mounted) return;
      setState(() {
        _members = members;
        if (withLoading) {
          _loading = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (withLoading) {
          _loading = false;
        }
        _error = '$e';
      });
    }
  }

  Future<void> _ensureRealtime() async {
    _rt ??= context.read<RealtimeClient>();
    final rt = _rt!;

    if (!rt.isConnected) {
      await rt.connect();
    }

    _rtSub ??= rt.events.listen((evt) {
      final t = evt.type;
      if (t != 'member_added' &&
          t != 'member_removed' &&
          t != 'member_role_changed') {
        return;
      }

      final evtChatId = _asInt(evt.data['chat_id'] ?? evt.data['chatId']);
      if (evtChatId != widget.chatId) return;

      final removedUserId = _asInt(evt.data['user_id'] ?? evt.data['userId']);
      if (t == 'member_removed' && removedUserId == widget.myUserId) {
        if (!mounted) return;
        showGlassSnack(
          context,
          'Вы были удалены из этого чата',
          kind: GlassSnackKind.info,
        );
        Navigator.of(context).maybePop();
        return;
      }

      _realtimeReloadDebounce?.cancel();
      _realtimeReloadDebounce = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        _reload(withLoading: false);
      });
    });
  }

  Set<int> _existingMemberIds() {
    return _members.map((m) => m.userId).toSet();
  }

  void _runMemberSearch(String query) {
    final q = query.trim();
    final seq = ++_memberSearchSeq;
    if (q.isEmpty) {
      setState(() {
        _memberSearching = false;
        _memberSearchError = null;
        _memberSearchResults = const [];
      });
      return;
    }

    setState(() {
      _memberSearching = true;
      _memberSearchError = null;
    });

    widget.repo
        .searchUsers(q)
        .then((users) {
          if (!mounted || seq != _memberSearchSeq) return;
          final existing = _existingMemberIds();
          final filtered = users
              .where((u) => !existing.contains(int.tryParse(u.id) ?? 0))
              .toList(growable: false);
          setState(() {
            _memberSearching = false;
            _memberSearchError = null;
            _memberSearchResults = filtered;
          });
        })
        .catchError((e) {
          if (!mounted || seq != _memberSearchSeq) return;
          setState(() {
            _memberSearching = false;
            _memberSearchError = e.toString();
            _memberSearchResults = const [];
          });
        });
  }

  void _scheduleMemberSearch(String query) {
    _memberSearchDebounce?.cancel();
    _memberSearchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      _runMemberSearch(query);
    });
  }

  Future<void> _addMember() async {
    if (!_canManage || _busy) return;
    final userId = int.tryParse(_memberIdCtrl.text.trim()) ?? 0;
    if (userId <= 0) {
      showGlassSnack(
        context,
        'Укажите корректный ID пользователя',
        kind: GlassSnackKind.error,
      );
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      await widget.repo.addMember(
        widget.chatId,
        userId: userId,
        role: _newMemberRole,
      );
      _memberIdCtrl.clear();
      _memberSearchCtrl.clear();
      _memberSearchResults = const [];
      _memberSearchError = null;
      await _reload();
      if (!mounted) return;
      showGlassSnack(
        context,
        'Участник добавлен',
        kind: GlassSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, '$e', kind: GlassSnackKind.error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _setRole(ChatMember member, String role) async {
    if (!_canManage || _busy) return;
    setState(() {
      _busy = true;
    });
    try {
      await widget.repo.updateMemberRole(
        widget.chatId,
        userId: member.userId,
        role: role,
      );
      await _reload();
      if (!mounted) return;
      showGlassSnack(
        context,
        'Роль обновлена (${member.username})',
        kind: GlassSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, '$e', kind: GlassSnackKind.error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _removeMember(ChatMember member) async {
    if (!_canManage || _busy) return;
    if (member.userId == widget.myUserId) {
      showGlassSnack(
        context,
        'Себя через этот sheet удалить нельзя',
        kind: GlassSnackKind.info,
      );
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      await widget.repo.removeMember(widget.chatId, userId: member.userId);
      await _reload();
      if (!mounted) return;
      showGlassSnack(
        context,
        'Участник удалён (${member.username})',
        kind: GlassSnackKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, '$e', kind: GlassSnackKind.error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _showMemberActionsAt(
    ChatMember member,
    Offset globalPosition,
  ) async {
    final role = member.role.trim().toLowerCase();
    final canChangeRole =
        _canManage && member.userId != widget.myUserId && role != 'owner';
    final canRemove = canChangeRole;
    if (!canChangeRole) return;

    final action = await RenContextMenu.show<String>(
      context,
      globalPosition: globalPosition,
      entries: [
        if (role != 'admin')
          RenContextMenuEntry.action(
            RenContextMenuAction<String>(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedShield01, size: 18),
              label: 'Сделать admin',
              value: 'admin',
            ),
          ),
        if (role != 'member')
          RenContextMenuEntry.action(
            RenContextMenuAction<String>(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedUser, size: 18),
              label: 'Сделать member',
              value: 'member',
            ),
          ),
        if (canRemove) ...[
          const RenContextMenuEntry.divider(),
          RenContextMenuEntry.action(
            RenContextMenuAction<String>(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: 18),
              label: 'Удалить из чата',
              value: 'remove',
              danger: true,
            ),
          ),
        ],
      ],
    );

    if (!mounted || action == null) return;
    if (action == 'remove') {
      await _removeMember(member);
      return;
    }
    await _setRole(member, action);
  }

  String _roleLabel(String role) {
    switch (role.trim().toLowerCase()) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      default:
        return 'Member';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return DraggableScrollableSheet(
      initialChildSize: 0.74,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return GlassSurface(
          blurSigma: 16,
          borderRadiusGeometry: const BorderRadius.only(
            topLeft: Radius.circular(26),
            topRight: Radius.circular(26),
          ),
          borderColor: baseInk.withOpacity(isDark ? 0.22 : 0.12),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.chatKind == 'channel'
                    ? 'Участники канала'
                    : 'Участники группы',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Всего: ${_members.length} • '
                '${_canManage ? "у вас есть права управления" : "только просмотр"}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.72),
                ),
              ),
              const SizedBox(height: 12),
              if (_canManage) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _memberSearchCtrl,
                  onChanged: _scheduleMemberSearch,
                  cursorColor: theme.colorScheme.primary,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Имя пользователя',
                    suffixIcon: _memberSearchCtrl.text.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    _memberSearchCtrl.clear();
                                    _memberSearchDebounce?.cancel();
                                    setState(() {
                                      _memberSearching = false;
                                      _memberSearchError = null;
                                      _memberSearchResults = const [];
                                    });
                                  },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: false,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_memberSearching)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                else if (_memberSearchError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _memberSearchError!.replaceFirst('Exception: ', ''),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  )
                else if (_memberSearchResults.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      children: _memberSearchResults
                          .map((u) {
                            final uid = int.tryParse(u.id) ?? 0;
                            if (uid <= 0) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassSurface(
                                borderRadius: 14,
                                blurSigma: 8,
                                borderColor: baseInk.withOpacity(
                                  isDark ? 0.14 : 0.08,
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    RenAvatar(
                                      url: u.avatarUrl,
                                      name: u.name,
                                      isOnline: false,
                                      size: 34,
                                      onlineDotSize: 0,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            u.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          Text(
                                            'ID: $uid',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
                                                      .withOpacity(0.7),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    GlassSurface(
                                      borderRadius: 10,
                                      blurSigma: 12,
                                      width: 32,
                                      height: 32,
                                      onTap: _busy
                                          ? null
                                          : () async {
                                              _memberIdCtrl.text = '$uid';
                                              await _addMember();
                                            },
                                      child: Center(
                                        child: HugeIcon(
                                          icon: HugeIcons.strokeRoundedAdd01,
                                          size: 16,
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.85),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    _error!.replaceFirst('Exception: ', ''),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                )
              else if (_members.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Список участников пуст',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                )
              else
                ..._members.map((member) {
                  final role = member.role.trim().toLowerCase();
                  final canChangeRole =
                      _canManage &&
                      member.userId != widget.myUserId &&
                      role != 'owner';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassSurface(
                      borderRadius: 16,
                      blurSigma: 10,
                      borderColor: baseInk.withOpacity(isDark ? 0.16 : 0.09),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(
                        children: [
                          RenAvatar(
                            url: member.avatarUrl,
                            name: member.username,
                            isOnline: false,
                            size: 38,
                            onlineDotSize: 0,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${member.userId} • ${_roleLabel(member.role)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.72),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (canChangeRole)
                            Builder(
                              builder: (buttonContext) {
                                return GlassSurface(
                                  borderRadius: 10,
                                  blurSigma: 10,
                                  width: 34,
                                  height: 34,
                                  onTap: _busy
                                      ? null
                                      : () async {
                                          final box = buttonContext
                                              .findRenderObject();
                                          if (box is! RenderBox) return;
                                          final origin = box.localToGlobal(
                                            Offset.zero,
                                          );
                                          final globalPosition = Offset(
                                            origin.dx - 170,
                                            origin.dy + box.size.height + 4,
                                          );
                                          await _showMemberActionsAt(
                                            member,
                                            globalPosition,
                                          );
                                        },
                                  child: Center(
                                    child: Icon(
                                      Icons.more_horiz_rounded,
                                      size: 18,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.82),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
