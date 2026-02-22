import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:ren/features/profile/presentation/profile_store.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';
import 'package:ren/shared/widgets/glass_surface.dart';

class ProfileEditSheet {
  static Future<void> show(BuildContext context) async {
    await GlassOverlays.showGlassBottomSheet<void>(
      context,
      builder: (context) => const _ProfileEditSheetBody(),
    );
  }
}

class ProfileEditPage extends StatelessWidget {
  const ProfileEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: const SafeArea(child: _ProfileEditContent(showDragHandle: false)),
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
          child: _ProfileEditContent(
            scrollController: scrollController,
            showDragHandle: true,
          ),
        );
      },
    );
  }
}

class _ProfileEditContent extends StatefulWidget {
  final ScrollController? scrollController;
  final bool showDragHandle;

  const _ProfileEditContent({
    this.scrollController,
    required this.showDragHandle,
  });

  @override
  State<_ProfileEditContent> createState() => _ProfileEditContentState();
}

class _ProfileEditContentState extends State<_ProfileEditContent> {
  final _usernameController = TextEditingController();
  final _picker = ImagePicker();

  bool _didSeedUsername = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<ProfileStore>();
    if (store.user == null) {
      store.loadMe();
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p.characters.first).take(2).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

  void _seedUsernameOnce(ProfileStore store) {
    if (_didSeedUsername || store.user == null) return;
    _usernameController.text = store.user!.username;
    _didSeedUsername = true;
  }

  Future<void> _pickAvatar() async {
    final source = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (source == null || !mounted) return;

    final croppedFile = await AvatarCropEditor.show(context, File(source.path));
    if (croppedFile == null || !mounted) return;

    final ok = await context.read<ProfileStore>().setAvatar(croppedFile);
    if (!mounted) return;

    final store = context.read<ProfileStore>();
    if (!ok && store.error != null) {
      showGlassSnack(context, store.error!, kind: GlassSnackKind.error);
    }

    try {
      await croppedFile.delete();
    } catch (_) {}
  }

  Future<void> _removeAvatar() async {
    final ok = await context.read<ProfileStore>().removeAvatar();
    if (!mounted) return;
    final store = context.read<ProfileStore>();
    if (!ok && store.error != null) {
      showGlassSnack(context, store.error!, kind: GlassSnackKind.error);
    }
  }

  Future<void> _saveUsername() async {
    final value = _usernameController.text.trim();
    if (value.isEmpty) {
      showGlassSnack(
        context,
        'Введите имя пользователя',
        kind: GlassSnackKind.error,
      );
      return;
    }

    final ok = await context.read<ProfileStore>().changeUsername(value);
    if (!mounted) return;

    final store = context.read<ProfileStore>();
    if (!ok && store.error != null) {
      showGlassSnack(context, store.error!, kind: GlassSnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseInk = isDark ? Colors.white : Colors.black;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Consumer<ProfileStore>(
      builder: (context, store, _) {
        final user = store.user;
        _seedUsernameOnce(store);

        return ListView(
          controller: widget.scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(16, 10, 16, 22 + bottomInset),
          children: [
            if (widget.showDragHandle)
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
            if (widget.showDragHandle) const SizedBox(height: 12),
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
                      child: ClipOval(
                        child: (user?.avatar ?? '').isEmpty
                            ? ColoredBox(
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
                                errorBuilder: (context, error, stackTrace) {
                                  return ColoredBox(
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
                            borderColor: baseInk.withOpacity(
                              isDark ? 0.20 : 0.10,
                            ),
                            onTap: store.isLoading ? null : _pickAvatar,
                            child: Center(
                              child: Text(
                                store.isLoading
                                    ? 'Загрузка...'
                                    : 'Выбрать фото',
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
                            borderColor: baseInk.withOpacity(
                              isDark ? 0.20 : 0.10,
                            ),
                            onTap: store.isLoading ? null : _removeAvatar,
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
                      enabled: !store.isLoading,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      cursorColor: theme.colorScheme.onSurface,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!store.isLoading) {
                          _saveUsername();
                        }
                      },
                      maxLength: 32,
                      decoration: InputDecoration(
                        labelText: 'Имя (username)',
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
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: baseInk.withOpacity(isDark ? 0.18 : 0.12),
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

class AvatarCropEditor extends StatefulWidget {
  final File imageFile;

  const AvatarCropEditor({super.key, required this.imageFile});

  static Future<File?> show(BuildContext context, File imageFile) {
    return Navigator.of(context).push<File?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AvatarCropEditor(imageFile: imageFile),
      ),
    );
  }

  @override
  State<AvatarCropEditor> createState() => _AvatarCropEditorState();
}

class _AvatarCropEditorState extends State<AvatarCropEditor> {
  final _controller = CropController();

  Uint8List? _imageBytes;
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      if (!mounted) return;
      setState(() => _imageBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      showGlassSnack(
        context,
        'Не удалось открыть изображение',
        kind: GlassSnackKind.error,
      );
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _onCropped(CropResult result) async {
    if (!mounted) return;

    if (result case CropFailure()) {
      setState(() => _isCropping = false);
      showGlassSnack(
        context,
        'Ошибка при обрезке изображения',
        kind: GlassSnackKind.error,
      );
      return;
    }

    final bytes = (result as CropSuccess).croppedImage;
    final ext = _preferredExtension(widget.imageFile.path);
    final tempPath =
        '${Directory.systemTemp.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final file = File(tempPath);

    try {
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      Navigator.of(context).pop(file);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCropping = false);
      showGlassSnack(
        context,
        'Не удалось сохранить изображение',
        kind: GlassSnackKind.error,
      );
    }
  }

  String _preferredExtension(String path) {
    final name = path.split('/').last.toLowerCase();
    if (name.endsWith('.png')) return 'png';
    if (name.endsWith('.webp')) return 'webp';
    if (name.endsWith('.jpeg') || name.endsWith('.jpg')) return 'jpg';
    return 'jpg';
  }

  void _startCrop() {
    if (_isCropping) return;
    setState(() => _isCropping = true);
    _controller.crop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close, color: Colors.white),
        ),
        title: const Text(
          'Настройка аватарки',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          if (_isCropping)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _imageBytes == null ? null : _startCrop,
              child: const Text(
                'Готово',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: _imageBytes == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                Expanded(
                  child: Crop(
                    image: _imageBytes!,
                    controller: _controller,
                    withCircleUi: true,
                    aspectRatio: 1,
                    interactive: true,
                    fixCropRect: true,
                    initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
                      size: 0.85,
                      aspectRatio: 1,
                    ),
                    maskColor: Colors.black.withOpacity(0.62),
                    baseColor: Colors.black,
                    progressIndicator: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    onCropped: _onCropped,
                  ),
                ),
                Container(
                  width: double.infinity,
                  color: Colors.black,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  child: Text(
                    'Масштабируйте и перемещайте фото, чтобы выбрать область аватарки',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
