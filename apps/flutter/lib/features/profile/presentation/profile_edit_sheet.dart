import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:ren/features/profile/presentation/profile_store.dart';
import 'package:ren/shared/widgets/glass_overlays.dart';
import 'package:ren/shared/widgets/glass_surface.dart';
import 'package:ren/shared/widgets/glass_snackbar.dart';

class ProfileEditSheet {
  static Future<void> show(BuildContext context) async {
    await GlassOverlays.showGlassBottomSheet<void>(
      context,
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


  Future<void> _saveUsername() async {
    final value = _usernameController.text.trim();
    if (value.isEmpty) return;

    final ok = await context.read<ProfileStore>().changeUsername(value);
    if (!mounted) return;

    final store = context.read<ProfileStore>();
    if (!ok && store.error != null) {
      showGlassSnack(context, store.error!, kind: GlassSnackKind.error);
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
    // Шаг 1: Выбираем изображение из галереи
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100, // Берем максимальное качество для редактирования
    );
    if (x == null) return;
    if (!mounted) return;

    // Шаг 2: Кроп 1:1 (пользователь выбирает область будущей аватарки)
    final cropper = ImageCropper();
    final cropped = await cropper.cropImage(
      sourcePath: x.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Настройка аватарки',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Настройка аватарки',
          aspectRatioLockEnabled: true,
        ),
      ],
    );

    if (cropped == null) return;
    if (!mounted) return;

    final croppedFile = File(cropped.path);

    // Шаг 3: Загружаем обработанное изображение на сервер
    final ok = await context.read<ProfileStore>().setAvatar(croppedFile);
    if (!mounted) return;

    final store = context.read<ProfileStore>();
    if (!ok && store.error != null) {
      showGlassSnack(context, store.error!, kind: GlassSnackKind.error);
    } else if (ok) {
      // Удаляем временный файл после успешной загрузки
      try {
        await croppedFile.delete();
      } catch (_) {}
    }
  }

  Future<void> _saveUsername() async {
    final value = _usernameController.text.trim();
    if (value.isEmpty) return;

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
                                      showGlassSnack(context, st.error!, kind: GlassSnackKind.error);
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

class AvatarCropEditor extends StatefulWidget {
  final File imageFile;
  final Function(File) onCropComplete;

  const AvatarCropEditor({
    super.key,
    required this.imageFile,
    required this.onCropComplete,
  });

  static Future<File?> show(BuildContext context, File imageFile) async {
    return await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (context) => AvatarCropEditor(
          imageFile: imageFile,
          onCropComplete: (file) {
            Navigator.of(context).pop(file);
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<AvatarCropEditor> createState() => _AvatarCropEditorState();
}

class _AvatarCropEditorState extends State<AvatarCropEditor> {
  ui.Image? _image;
  double _scale = 1.0;
  Offset _position = Offset.zero;
  double _rotation = 0.0;
  
  int _selectedSize = 512;
  final List<int> _availableSizes = [256, 512, 1024];
  
  bool _isProcessing = false;
  
  double _baseScale = 1.0;
  Offset _basePosition = Offset.zero;
  
  // Минимальный и максимальный размер окна кропа
  double _minCropSize = 200;
  double _maxCropSize = 600;
  double _currentCropSize = 400;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await widget.imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _image = frame.image;
      _calculateCropSizeLimits();
    });
  }

  void _calculateCropSizeLimits() {
    if (_image == null) return;
    
    final imageWidth = _image!.width.toDouble();
    final imageHeight = _image!.height.toDouble();
    
    // Минимальная сторона изображения определяет максимальный размер кропа
    final minImageSide = imageWidth < imageHeight ? imageWidth : imageHeight;
    
    // Максимальный размер кропа = минимальная сторона изображения (чтобы поместилось всё)
    _maxCropSize = minImageSide;
    
    // Минимальный размер кропа = 200px или меньше если изображение маленькое
    _minCropSize = minImageSide < 200 ? minImageSide : 200;
    
    // Начальный размер кропа = максимальный (показываем всё изображение)
    _currentCropSize = _maxCropSize;
    
    // Если изображение квадратное (соотношение близко к 1:1), центрируем
    final aspectRatio = imageWidth / imageHeight;
    if ((aspectRatio - 1.0).abs() < 0.05) {
      // Квадратное изображение - позиция по центру
      _position = Offset.zero;
    } else {
      // Не квадратное - позиция зависит от того, какая сторона больше
      _position = Offset.zero;
    }
  }

  Future<void> _cropAndSave() async {
    if (_image == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final bytes = await widget.imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        throw Exception('Не удалось декодировать изображение');
      }

      final imageWidth = originalImage.width.toDouble();
      final imageHeight = originalImage.height.toDouble();

      // Получаем размер виджета
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) throw Exception('Не удалось получить размер виджета');

      final widgetSize = renderBox.size;
      final cropAreaSize = _currentCropSize;

      // Вычисляем какой размер изображения занимает в виджете
      final minImageSide = imageWidth < imageHeight ? imageWidth : imageHeight;
      
      // Масштаб отображения (сколько пикселей изображения в одном пикселе виджета)
      final displayScale = minImageSide / cropAreaSize;
      final actualScale = displayScale * _scale;

      // Размер области кропа в пикселях оригинального изображения
      final cropSizeInImage = (cropAreaSize * actualScale).toInt();

      // Центр области кропа в координатах виджета
      final cropCenterX = widgetSize.width / 2;
      final cropCenterY = widgetSize.height / 2;

      // Центр изображения в координатах виджета (с учетом позиции)
      final imageCenterX = cropCenterX + _position.dx;
      final imageCenterY = cropCenterY + _position.dy;

      // Смещение в пикселях оригинального изображения
      final offsetX = ((cropCenterX - imageCenterX) * actualScale);
      final offsetY = ((cropCenterY - imageCenterY) * actualScale);

      // Координаты кропа
      var x = ((imageWidth / 2) + offsetX - (cropSizeInImage / 2)).toInt();
      var y = ((imageHeight / 2) + offsetY - (cropSizeInImage / 2)).toInt();

      // Ограничиваем координаты
      x = x.clamp(0, (imageWidth - cropSizeInImage).toInt());
      y = y.clamp(0, (imageHeight - cropSizeInImage).toInt());

      // Обрезаем изображение
      var cropped = img.copyCrop(
        originalImage,
        x: x,
        y: y,
        width: cropSizeInImage,
        height: cropSizeInImage,
      );

      // Применяем поворот если есть
      if (_rotation != 0) {
        final angle = _rotation * (3.14159 / 180);
        cropped = img.copyRotate(cropped, angle: angle);
        
        // После поворота обрезаем до квадрата
        final minSide = cropped.width < cropped.height ? cropped.width : cropped.height;
        final cropX = ((cropped.width - minSide) / 2).toInt();
        final cropY = ((cropped.height - minSide) / 2).toInt();
        
        cropped = img.copyCrop(
          cropped,
          x: cropX,
          y: cropY,
          width: minSide,
          height: minSide,
        );
      }

      // Изменяем размер до выбранного разрешения
      cropped = img.copyResize(
        cropped,
        width: _selectedSize,
        height: _selectedSize,
        interpolation: img.Interpolation.linear,
      );

      // Сохраняем во временный файл
      final encoded = img.encodeJpg(cropped, quality: 90);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempPath = '${Directory.systemTemp.path}/cropped_avatar_$timestamp.jpg';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(encoded);

      widget.onCropComplete(tempFile);
    } catch (e) {
      if (mounted) {
        showGlassSnack(context, 'Ошибка обработки: $e', kind: GlassSnackKind.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Настройка аватарки',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          if (_isProcessing)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _cropAndSave,
              child: const Text(
                'Готово',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: _image == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onScaleStart: (details) {
                          _baseScale = _scale;
                          _basePosition = _position;
                        },
                        onScaleUpdate: (details) {
                          setState(() {
                            // Масштабирование
                            _scale = (_baseScale * details.scale).clamp(0.5, 5.0);
                            
                            // Перемещение
                            _position = _basePosition + details.focalPointDelta;
                          });
                        },
                        child: Container(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          color: Colors.black,
                          child: CustomPaint(
                            size: Size(constraints.maxWidth, constraints.maxHeight),
                            painter: _ImageCropPainter(
                              image: _image!,
                              scale: _scale,
                              position: _position,
                              rotation: _rotation,
                              cropSize: _currentCropSize,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Размер окна кропа
                      Row(
                        children: [
                          const Icon(Icons.crop_free, color: Colors.white70, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Размер кропа: ${_currentCropSize.toInt()}px',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                Slider(
                                  value: _currentCropSize,
                                  min: _minCropSize,
                                  max: _maxCropSize,
                                  activeColor: Colors.white,
                                  inactiveColor: Colors.white24,
                                  onChanged: (value) {
                                    setState(() {
                                      _currentCropSize = value;
                                      
                                      // Если размер кропа = максимальному (минимальная сторона изображения)
                                      // и изображение квадратное, центрируем
                                      if (_image != null) {
                                        final imageWidth = _image!.width.toDouble();
                                        final imageHeight = _image!.height.toDouble();
                                        final aspectRatio = imageWidth / imageHeight;
                                        final isSquare = (aspectRatio - 1.0).abs() < 0.05;
                                        final isMaxSize = (_currentCropSize - _maxCropSize).abs() < 1;
                                        
                                        if (isSquare && isMaxSize) {
                                          _position = Offset.zero;
                                        }
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Масштаб
                      Row(
                        children: [
                          const Icon(Icons.zoom_out, color: Colors.white70, size: 20),
                          Expanded(
                            child: Slider(
                              value: _scale,
                              min: 0.5,
                              max: 5.0,
                              activeColor: Colors.white,
                              inactiveColor: Colors.white24,
                              onChanged: (value) {
                                setState(() {
                                  _scale = value;
                                });
                              },
                            ),
                          ),
                          const Icon(Icons.zoom_in, color: Colors.white70, size: 20),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Поворот
                      Row(
                        children: [
                          const Icon(Icons.rotate_left, color: Colors.white70, size: 20),
                          Expanded(
                            child: Slider(
                              value: _rotation,
                              min: -180,
                              max: 180,
                              activeColor: Colors.white,
                              inactiveColor: Colors.white24,
                              onChanged: (value) {
                                setState(() {
                                  _rotation = value;
                                });
                              },
                            ),
                          ),
                          const Icon(Icons.rotate_right, color: Colors.white70, size: 20),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Выбор разрешения
                      Row(
                        children: [
                          const Text(
                            'Разрешение:',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: _availableSizes.map((size) {
                                final isSelected = size == _selectedSize;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedSize = size;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white12,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${size}px',
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.black
                                            : Colors.white70,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Используйте жесты для масштабирования и перемещения',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ImageCropPainter extends CustomPainter {
  final ui.Image image;
  final double scale;
  final Offset position;
  final double rotation;
  final double cropSize;

  _ImageCropPainter({
    required this.image,
    required this.scale,
    required this.position,
    required this.rotation,
    required this.cropSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Область кропа (квадрат с динамическим размером)
    final cropRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cropSize,
      height: cropSize,
    );

    // Вычисляем размеры для отображения изображения
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    final minImageSide = imageWidth < imageHeight ? imageWidth : imageHeight;
    
    // Размер изображения на экране (относительно размера кропа)
    final displaySize = (minImageSide / cropSize) * cropSize * scale;
    
    final imageAspect = imageWidth / imageHeight;
    double displayWidth, displayHeight;
    
    if (imageAspect > 1) {
      // Горизонтальное изображение
      displayWidth = displaySize;
      displayHeight = displaySize / imageAspect;
    } else {
      // Вертикальное изображение
      displayHeight = displaySize;
      displayWidth = displaySize * imageAspect;
    }

    // Позиция изображения (центр + смещение)
    final imageRect = Rect.fromCenter(
      center: Offset(size.width / 2 + position.dx, size.height / 2 + position.dy),
      width: displayWidth,
      height: displayHeight,
    );

    // Рисуем затемнение
    canvas.saveLayer(Rect.largest, Paint());
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black.withOpacity(0.7),
    );
    canvas.drawRect(
      cropRect,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();

    // Рисуем изображение
    canvas.save();
    
    // Применяем поворот вокруг центра изображения
    if (rotation != 0) {
      canvas.translate(imageRect.center.dx, imageRect.center.dy);
      canvas.rotate(rotation * (3.14159 / 180));
      canvas.translate(-imageRect.center.dx, -imageRect.center.dy);
    }

    // Рисуем изображение
    final srcRect = Rect.fromLTWH(
      0,
      0,
      imageWidth,
      imageHeight,
    );

    canvas.drawImageRect(image, srcRect, imageRect, Paint());
    canvas.restore();

    // Рисуем рамку области кропа
    canvas.drawRect(
      cropRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Рисуем сетку 3x3
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 1;
    
    for (int i = 1; i < 3; i++) {
      final x = cropRect.left + (cropRect.width * i / 3);
      canvas.drawLine(
        Offset(x, cropRect.top),
        Offset(x, cropRect.bottom),
        gridPaint,
      );
      
      final y = cropRect.top + (cropRect.height * i / 3);
      canvas.drawLine(
        Offset(cropRect.left, y),
        Offset(cropRect.right, y),
        gridPaint,
      );
    }
    
    // Рисуем углы для лучшей визуализации
    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    
    final cornerLength = 20.0;
    
    // Левый верхний угол
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top),
      Offset(cropRect.left + cornerLength, cropRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top),
      Offset(cropRect.left, cropRect.top + cornerLength),
      cornerPaint,
    );
    
    // Правый верхний угол
    canvas.drawLine(
      Offset(cropRect.right, cropRect.top),
      Offset(cropRect.right - cornerLength, cropRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.top),
      Offset(cropRect.right, cropRect.top + cornerLength),
      cornerPaint,
    );
    
    // Левый нижний угол
    canvas.drawLine(
      Offset(cropRect.left, cropRect.bottom),
      Offset(cropRect.left + cornerLength, cropRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.bottom),
      Offset(cropRect.left, cropRect.bottom - cornerLength),
      cornerPaint,
    );
    
    // Правый нижний угол
    canvas.drawLine(
      Offset(cropRect.right, cropRect.bottom),
      Offset(cropRect.right - cornerLength, cropRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.bottom),
      Offset(cropRect.right, cropRect.bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(_ImageCropPainter oldDelegate) {
    return oldDelegate.scale != scale ||
        oldDelegate.position != position ||
        oldDelegate.rotation != rotation ||
        oldDelegate.cropSize != cropSize;
  }
}