import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:path_provider/path_provider.dart';

import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';

class BackgroundSettings extends ChangeNotifier {
  ImageProvider? _backgroundImage;
  double _imageOpacity = 1.0;
  double _imageBlurSigma = 0.0;
  Color _autoSeedLight = const Color(0xFF3B82F6);
  Color _autoSeedDark = const Color(0xFF8B5CF6);

  String? _backgroundType;
  String? _backgroundValue;

  final List<String> _galleryHistoryPaths = [];

  List<String> get galleryHistoryPaths =>
      List.unmodifiable(_galleryHistoryPaths);
  String? get currentFilePath =>
      _backgroundType == 'file' ? _backgroundValue : null;
  Color get autoSeedLight => _autoSeedLight;
  Color get autoSeedDark => _autoSeedDark;

  BackgroundSettings() {
    _load();
  }

  ImageProvider? get backgroundImage => _backgroundImage;
  double get imageOpacity => _imageOpacity;
  double get imageBlurSigma => _imageBlurSigma;

  Future<void> _load() async {
    final type = await SecureStorage.readKey(Keys.backgroundType);
    final value = await SecureStorage.readKey(Keys.backgroundValue);
    final imgOpacity = await SecureStorage.readKey(Keys.backgroundImageOpacity);
    final blur = await SecureStorage.readKey(Keys.backgroundImageBlur);
    final historyJson = await SecureStorage.readKey(
      Keys.backgroundGalleryHistory,
    );

    _backgroundType = type;
    _backgroundValue = value;

    if (imgOpacity != null) {
      _imageOpacity = double.tryParse(imgOpacity) ?? _imageOpacity;
    }
    if (blur != null) {
      _imageBlurSigma = double.tryParse(blur) ?? _imageBlurSigma;
    }

    _galleryHistoryPaths
      ..clear()
      ..addAll(_decodeHistory(historyJson));
    _galleryHistoryPaths.removeWhere((p) => !File(p).existsSync());

    _backgroundImage = _buildImageProvider(type, value);
    notifyListeners();
    unawaited(_refreshAutoSeeds());
  }

  List<String> _decodeHistory(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return const [];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  ImageProvider? _buildImageProvider(String? type, String? value) {
    if (type == null || value == null || value.isEmpty) return null;
    if (type == 'network') {
      return NetworkImage(value);
    }
    if (type == 'file') {
      final f = File(value);
      if (!f.existsSync()) return null;
      return FileImage(f);
    }
    return null;
  }

  Future<void> _persist() async {
    await SecureStorage.writeKey(
      Keys.backgroundImageOpacity,
      _imageOpacity.toString(),
    );
    await SecureStorage.writeKey(
      Keys.backgroundImageBlur,
      _imageBlurSigma.toString(),
    );

    await SecureStorage.writeKey(
      Keys.backgroundGalleryHistory,
      jsonEncode(_galleryHistoryPaths),
    );

    if (_backgroundType == null || _backgroundValue == null) {
      await SecureStorage.deleteKey(Keys.backgroundType);
      await SecureStorage.deleteKey(Keys.backgroundValue);
      return;
    }
    await SecureStorage.writeKey(Keys.backgroundType, _backgroundType!);
    await SecureStorage.writeKey(Keys.backgroundValue, _backgroundValue!);
  }

  void setBackgroundImage(ImageProvider? image) {
    _backgroundImage = image;
    if (image == null) {
      _backgroundType = null;
      _backgroundValue = null;
    } else if (image is NetworkImage) {
      _backgroundType = 'network';
      _backgroundValue = image.url;
    } else if (image is FileImage) {
      _backgroundType = 'file';
      _backgroundValue = image.file.path;
    } else {
      _backgroundType = null;
      _backgroundValue = null;
    }
    _persist();
    notifyListeners();
    unawaited(_refreshAutoSeeds());
  }

  void setBackgroundFromUrl(String url) {
    setBackgroundImage(NetworkImage(url));
  }

  void setBackgroundFromFilePath(String path) {
    setBackgroundImage(FileImage(File(path)));
  }

  Future<void> setBackgroundFromPickedFilePath(String pickedPath) async {
    final copiedPath = await _copyToAppDirectory(pickedPath);
    _rememberInHistory(copiedPath);
    setBackgroundFromFilePath(copiedPath);
  }

  void _rememberInHistory(String path) {
    if (path.isEmpty) return;
    _galleryHistoryPaths.remove(path);
    _galleryHistoryPaths.insert(0, path);
    const maxItems = 12;
    if (_galleryHistoryPaths.length > maxItems) {
      _galleryHistoryPaths.removeRange(maxItems, _galleryHistoryPaths.length);
    }
  }

  Future<String> _copyToAppDirectory(String pickedPath) async {
    final src = File(pickedPath);
    if (!src.existsSync()) {
      return pickedPath;
    }

    final dir = await getApplicationDocumentsDirectory();
    final wallpapersDir = Directory(
      '${dir.path}${Platform.pathSeparator}wallpapers',
    );
    if (!wallpapersDir.existsSync()) {
      wallpapersDir.createSync(recursive: true);
    }

    final ext = _safeExtension(pickedPath);
    final fileName = 'wallpaper_${DateTime.now().millisecondsSinceEpoch}$ext';
    final destPath = '${wallpapersDir.path}${Platform.pathSeparator}$fileName';
    await src.copy(destPath);
    return destPath;
  }

  String _safeExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return '.jpg';
    final ext = path.substring(dot);
    if (ext.length > 6) return '.jpg';
    return ext;
  }

  void setImageOpacity(double value) {
    _imageOpacity = value.clamp(0.0, 1.0);
    _persist();
    notifyListeners();
  }

  void setImageBlurSigma(double value) {
    _imageBlurSigma = value.clamp(0.0, 30.0);
    _persist();
    notifyListeners();
  }

  Future<void> _refreshAutoSeeds() async {
    Color? base;
    final value = _backgroundValue;

    if (_backgroundType == 'file' && value != null && value.isNotEmpty) {
      base = await _extractDominantColorFromFile(value);
    }

    if (base == null && value != null && value.isNotEmpty) {
      base = _colorFromTextHash(value);
    }

    base ??= const Color(0xFF6366F1);

    final nextLight = _normalizeSeed(base, brightness: Brightness.light);
    final nextDark = _normalizeSeed(base, brightness: Brightness.dark);

    if (nextLight == _autoSeedLight && nextDark == _autoSeedDark) {
      return;
    }

    _autoSeedLight = nextLight;
    _autoSeedDark = nextDark;
    notifyListeners();
  }

  Future<Color?> _extractDominantColorFromFile(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return await _extractDominantColorFromBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<Color?> _extractDominantColorFromBytes(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 40,
        targetHeight: 40,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      image.dispose();
      if (byteData == null) return null;

      final data = byteData.buffer.asUint8List();
      var rTotal = 0.0;
      var gTotal = 0.0;
      var bTotal = 0.0;
      var weightTotal = 0.0;

      for (var i = 0; i + 3 < data.length; i += 4) {
        final alpha = data[i + 3] / 255.0;
        if (alpha < 0.1) continue;

        final r = data[i].toDouble();
        final g = data[i + 1].toDouble();
        final b = data[i + 2].toDouble();

        final max = [r, g, b].reduce((a, c) => a > c ? a : c);
        final min = [r, g, b].reduce((a, c) => a < c ? a : c);
        final saturationWeight = ((max - min) / 255.0).clamp(0.15, 1.0);
        final weight = alpha * saturationWeight;

        rTotal += r * weight;
        gTotal += g * weight;
        bTotal += b * weight;
        weightTotal += weight;
      }

      if (weightTotal <= 0) return null;

      return Color.fromARGB(
        255,
        (rTotal / weightTotal).round().clamp(0, 255),
        (gTotal / weightTotal).round().clamp(0, 255),
        (bTotal / weightTotal).round().clamp(0, 255),
      );
    } catch (_) {
      return null;
    }
  }

  Color _colorFromTextHash(String input) {
    var hash = 0;
    for (final unit in input.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    final saturation = 0.58 + (((hash >> 8) % 22) / 100.0);
    return HSLColor.fromAHSL(
      1,
      hue,
      saturation.clamp(0.50, 0.80),
      0.52,
    ).toColor();
  }

  Color _normalizeSeed(Color color, {required Brightness brightness}) {
    final hsl = HSLColor.fromColor(color);
    final targetLightness = brightness == Brightness.dark ? 0.62 : 0.48;
    final targetSaturation = brightness == Brightness.dark ? 0.64 : 0.72;
    return hsl
        .withLightness(targetLightness)
        .withSaturation(targetSaturation)
        .toColor();
  }
}

class BackgroundPresets {
  static const List<String> wallpaperUrls = [];
}
