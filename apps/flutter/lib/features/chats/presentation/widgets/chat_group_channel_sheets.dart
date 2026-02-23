import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:ren/features/chats/data/chats_repository.dart';
import 'package:ren/features/chats/domain/chat_models.dart';
import 'package:ren/features/profile/presentation/widgets/profile_edit_sheet.dart';
import 'package:ren/shared/widgets/avatar.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class EditGroupChannelSheet extends StatefulWidget {
  final ChatPreview chat;

  const EditGroupChannelSheet({super.key, required this.chat});

  @override
  State<EditGroupChannelSheet> createState() => _EditGroupChannelSheetState();
}

class _EditGroupChannelSheetState extends State<EditGroupChannelSheet> {
  final _titleCtrl = TextEditingController();
  File? _newAvatar;
  bool _removeAvatar = false;
  bool _isSaving = false;

  ChatsRepository get _repo => context.read<ChatsRepository>();

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = widget.chat.user.name.trim();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final source = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 96,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (source == null || !mounted) return;
    final cropped = await AvatarCropEditor.show(context, File(source.path));
    if (cropped == null || !mounted) return;
    setState(() {
      _newAvatar = cropped;
      _removeAvatar = false;
    });
  }

  void _markAvatarForRemove() {
    setState(() {
      _newAvatar = null;
      _removeAvatar = true;
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final chatId = int.tryParse(widget.chat.id) ?? 0;
    if (chatId <= 0) return;

    final nextTitle = _titleCtrl.text.trim();
    if (nextTitle.isEmpty) {
      showGlassSnack(context, 'Введите название', kind: GlassSnackKind.error);
      return;
    }

    final initialTitle = widget.chat.user.name.trim();
    final hadAvatar = widget.chat.user.avatarUrl.trim().isNotEmpty;
    final titleChanged = nextTitle != initialTitle;
    final avatarChanged = _newAvatar != null || (_removeAvatar && hadAvatar);
    if (!titleChanged && !avatarChanged) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (titleChanged) {
        await _repo.updateChatInfo(chatId, title: nextTitle);
      }
      if (_newAvatar != null) {
        await _repo.uploadChatAvatar(chatId, _newAvatar!);
      } else if (_removeAvatar && hadAvatar) {
        await _repo.removeChatAvatar(chatId);
      }
      if (!mounted) return;
      showGlassSnack(
        context,
        'Изменения сохранены',
        kind: GlassSnackKind.success,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, e.toString(), kind: GlassSnackKind.error);
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final currentAvatarUrl = widget.chat.user.avatarUrl.trim();

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 12),
      child: GlassSurface(
        borderRadius: 24,
        blurSigma: 16,
        borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.10),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Редактирование',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: SizedBox(
                width: 94,
                height: 94,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(47),
                  child: _newAvatar != null
                      ? Image.file(_newAvatar!, fit: BoxFit.cover)
                      : (_removeAvatar || currentAvatarUrl.isEmpty)
                      ? Container(
                          color: theme.colorScheme.surface,
                          alignment: Alignment.center,
                          child: Text(
                            (widget.chat.user.name.isNotEmpty
                                    ? widget.chat.user.name[0]
                                    : '?')
                                .toUpperCase(),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : Image.network(
                          currentAvatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return Container(
                              color: theme.colorScheme.surface,
                              alignment: Alignment.center,
                              child: Text(
                                (widget.chat.user.name.isNotEmpty
                                        ? widget.chat.user.name[0]
                                        : '?')
                                    .toUpperCase(),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : _pickAvatar,
                  child: const Text('Сменить аватар'),
                ),
                if (_newAvatar != null ||
                    (!_removeAvatar && currentAvatarUrl.isNotEmpty))
                  TextButton(
                    onPressed: _isSaving ? null : _markAvatarForRemove,
                    child: const Text('Удалить'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtrl,
              maxLength: 80,
              textInputAction: TextInputAction.done,
              enabled: !_isSaving,
              decoration: InputDecoration(
                labelText: 'Название',
                labelStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.75),
                ),
                filled: true,
                fillColor: Colors.transparent,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: baseInk.withOpacity(isDark ? 0.28 : 0.18),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: baseInk.withOpacity(isDark ? 0.28 : 0.18),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1.5,
                  ),
                ),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: Text(_isSaving ? 'Сохранение...' : 'Сохранить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CreateGroupChannelSheet extends StatefulWidget {
  final String kind;
  final String initialTitle;
  final Future<void> Function(ChatPreview createdChat)? onCreated;

  const CreateGroupChannelSheet({
    super.key,
    required this.kind,
    this.initialTitle = '',
    this.onCreated,
  });

  @override
  State<CreateGroupChannelSheet> createState() =>
      _CreateGroupChannelSheetState();
}

class _CreateGroupChannelSheetState extends State<CreateGroupChannelSheet> {
  final _titleCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final Set<int> _selectedUserIds = <int>{};
  final Map<int, ChatUser> _selectedUsers = <int, ChatUser>{};
  bool _isSearching = false;
  String? _searchError;
  List<ChatUser> _searchResults = const [];
  int _searchSeq = 0;
  Timer? _searchDebounce;
  bool _isCreating = false;

  ChatsRepository get _repo => context.read<ChatsRepository>();

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = widget.initialTitle;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _runSearch(String query) {
    final q = query.trim();
    final seq = ++_searchSeq;

    if (q.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchError = null;
        _searchResults = const [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    _repo
        .searchUsers(q)
        .then((users) {
          if (!mounted || seq != _searchSeq) return;
          final existing = _selectedUserIds;
          final filtered = users
              .where((u) => !existing.contains(int.tryParse(u.id) ?? 0))
              .toList(growable: false);
          setState(() {
            _isSearching = false;
            _searchError = null;
            _searchResults = filtered;
          });
        })
        .catchError((e) {
          if (!mounted || seq != _searchSeq) return;
          setState(() {
            _isSearching = false;
            _searchError = e.toString();
            _searchResults = const [];
          });
        });
  }

  void _scheduleSearch(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _runSearch(query);
    });
  }

  void _toggleUser(ChatUser user) {
    final userId = int.tryParse(user.id) ?? 0;
    if (userId <= 0) return;

    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
        _selectedUsers.remove(userId);
      } else {
        _selectedUserIds.add(userId);
        _selectedUsers[userId] = user;
      }
    });
  }

  Future<void> _create() async {
    if (_isCreating) return;

    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      showGlassSnack(context, 'Укажите название', kind: GlassSnackKind.error);
      return;
    }

    final memberIds = _selectedUserIds.toList(growable: false);

    setState(() {
      _isCreating = true;
    });

    try {
      final chat = widget.kind == 'group'
          ? await _repo.createGroupChat(title: title, memberUserIds: memberIds)
          : await _repo.createChannel(title: title, memberUserIds: memberIds);

      if (!mounted) return;
      Navigator.of(context).pop(true);

      await widget.onCreated?.call(chat);
    } catch (e) {
      if (!mounted) return;
      showGlassSnack(context, e.toString(), kind: GlassSnackKind.error);
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
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
                widget.kind == 'group' ? 'Новая группа' : 'Новый канал',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              GlassSurface(
                borderRadius: 14,
                blurSigma: 8,
                borderColor: baseInk.withOpacity(isDark ? 0.14 : 0.08),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Название',
                    border: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Участники',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GlassSurface(
                borderRadius: 14,
                blurSigma: 8,
                borderColor: baseInk.withOpacity(isDark ? 0.14 : 0.08),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _scheduleSearch,
                        decoration: InputDecoration(
                          hintText: 'Поиск пользователей',
                          border: InputBorder.none,
                          filled: false,
                          isDense: true,
                          suffixIcon: _searchCtrl.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _searchDebounce?.cancel();
                                    setState(() {
                                      _isSearching = false;
                                      _searchError = null;
                                      _searchResults = const [];
                                    });
                                  },
                                ),
                        ),
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _searchError!.replaceFirst('Exception: ', ''),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                )
              else if (_searchResults.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    children: _searchResults
                        .map((user) {
                          final uid = int.tryParse(user.id) ?? 0;
                          if (uid <= 0) return const SizedBox.shrink();
                          final isSelected = _selectedUserIds.contains(uid);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GlassSurface(
                              borderRadius: 14,
                              blurSigma: 8,
                              borderColor: isSelected
                                  ? theme.colorScheme.primary.withOpacity(0.5)
                                  : baseInk.withOpacity(isDark ? 0.14 : 0.08),
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _toggleUser(user),
                                child: Row(
                                  children: [
                                    RenAvatar(
                                      url: user.avatarUrl,
                                      name: user.name,
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
                                            user.name,
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
                                    if (isSelected)
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundColor:
                                            theme.colorScheme.primary,
                                        child: const Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      )
                                    else
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundColor: theme
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.12),
                                        child: const Icon(
                                          Icons.add_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
              if (_selectedUsers.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Выбрано: ${_selectedUsers.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedUsers.values.map((user) {
                    return GlassSurface(
                      borderRadius: 20,
                      blurSigma: 8,
                      borderColor: theme.colorScheme.primary.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RenAvatar(
                            url: user.avatarUrl,
                            name: user.name,
                            isOnline: false,
                            size: 24,
                            onlineDotSize: 0,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            user.name,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _toggleUser(user),
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close_rounded, size: 14),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isCreating ? null : _create,
                  child: _isCreating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Создать'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
