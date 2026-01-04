import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:ren/features/profile/presentation/profile_store.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ProfileEditSheet {
  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (context) {
        return const _ProfileEditSheetBody();
      },
    );
  }
}

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _usernameController = TextEditingController();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final store = context.read<ProfileStore>();
    if (store.user == null) {
      store.loadMe();
    } else {
      _usernameController.text = store.user?.username ?? '';
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p.characters.first).take(2).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

  Future<void> _pickAvatar() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (x == null) return;
    if (!mounted) return;

    final ok = await context.read<ProfileStore>().setAvatar(File(x.path));
    if (!mounted) return;

    final store = context.read<ProfileStore>();
    if (!ok && store.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.error!)),
      );
    }
  }

  Future<void> _saveUsername() async {
    final value = _usernameController.text.trim();
    if (value.isEmpty) return;

    final ok = await context.read<ProfileStore>().changeUsername(value);
    if (!mounted) return;

    final store = context.read<ProfileStore>();
    if (!ok && store.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
      ),
      body: SafeArea(
        child: _ProfileEditContent(
          usernameController: _usernameController,
          picker: _picker,
        ),
      ),
    );
  }
}

class _ProfileEditSheetBody extends StatelessWidget {
  const _ProfileEditSheetBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
            children: const [
              _ProfileEditContent(),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileEditContent extends StatefulWidget {
  final TextEditingController? usernameController;
  final ImagePicker? picker;

  const _ProfileEditContent({this.usernameController, this.picker});

  @override
  State<_ProfileEditContent> createState() => _ProfileEditContentState();
}

class _ProfileEditContentState extends State<_ProfileEditContent> {
  late final TextEditingController _usernameController;
  late final ImagePicker _picker;

  @override
  void initState() {
    super.initState();
    _usernameController = widget.usernameController ?? TextEditingController();
    _picker = widget.picker ?? ImagePicker();

    final store = context.read<ProfileStore>();
    if (store.user == null) {
      store.loadMe();
    } else if (_usernameController.text.isEmpty) {
      _usernameController.text = store.user?.username ?? '';
    }
  }

  @override
  void dispose() {
    if (widget.usernameController == null) {
      _usernameController.dispose();
    }
    super.dispose();
  }

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p.characters.first).take(2).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

  Future<void> _pickAvatar() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (x == null) return;
    if (!mounted) return;

    final ok = await context.read<ProfileStore>().setAvatar(File(x.path));
    if (!mounted) return;

    final store = context.read<ProfileStore>();
    if (!ok && store.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.error!)),
      );
    }
  }

  Future<void> _saveUsername() async {
    final value = _usernameController.text.trim();
    if (value.isEmpty) return;

    final ok = await context.read<ProfileStore>().changeUsername(value);
    if (!mounted) return;

    final store = context.read<ProfileStore>();
    if (!ok && store.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;

    return Consumer<ProfileStore>(
      builder: (context, store, _) {
        final user = store.user;
        if (user != null && _usernameController.text.isEmpty) {
          _usernameController.text = user.username;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Профиль',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(
                    Icons.close_rounded,
                    color: theme.colorScheme.onSurface.withOpacity(0.9),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GlassSurface(
              borderRadius: 24,
              blurSigma: 14,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 104,
                      height: 104,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(52),
                        child: (user?.avatar ?? '').isEmpty
                            ? Container(
                                color: theme.colorScheme.surface,
                                child: Center(
                                  child: Text(
                                    _initials(user?.username ?? ''),
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 28,
                                    ),
                                  ),
                                ),
                              )
                            : Image.network(
                                user!.avatar!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stack) {
                                  return Container(
                                    color: theme.colorScheme.surface,
                                    child: Center(
                                      child: Text(
                                        _initials(user.username),
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 28,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GlassSurface(
                            borderRadius: 14,
                            blurSigma: 12,
                            height: 44,
                            borderColor:
                                baseInk.withOpacity(isDark ? 0.20 : 0.10),
                            onTap: store.isLoading ? null : _pickAvatar,
                            child: Center(
                              child: Text(
                                store.isLoading ? 'Загрузка...' : 'Выбрать фото',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GlassSurface(
                            borderRadius: 14,
                            blurSigma: 12,
                            height: 44,
                            color: const Color(0xFF991B1B).withOpacity(0.55),
                            borderColor:
                                baseInk.withOpacity(isDark ? 0.20 : 0.10),
                            onTap: store.isLoading
                                ? null
                                : () async {
                                    final ok = await context
                                        .read<ProfileStore>()
                                        .removeAvatar();
                                    if (!context.mounted) return;
                                    final st = context.read<ProfileStore>();
                                    if (!ok && st.error != null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(st.error!)),
                                      );
                                    }
                                  },
                            child: Center(
                              child: Text(
                                'Удалить',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Имя (username)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassSurface(
                      borderRadius: 14,
                      blurSigma: 12,
                      height: 46,
                      borderColor: baseInk.withOpacity(isDark ? 0.20 : 0.10),
                      onTap: store.isLoading ? null : _saveUsername,
                      child: Center(
                        child: Text(
                          store.isLoading ? 'Сохранение...' : 'Сохранить',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
