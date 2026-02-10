import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';

import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';

class BackgroundSettings extends ChangeNotifier {
  ImageProvider? _backgroundImage;
  double _imageOpacity = 1.0;
  double _imageBlurSigma = 0.0;

  String? _backgroundType;
  String? _backgroundValue;

  final List<String> _galleryHistoryPaths = [];

  List<String> get galleryHistoryPaths => List.unmodifiable(_galleryHistoryPaths);
  String? get currentFilePath => _backgroundType == 'file' ? _backgroundValue : null;

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
    final historyJson =
        await SecureStorage.readKey(Keys.backgroundGalleryHistory);

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
    final wallpapersDir = Directory('${dir.path}${Platform.pathSeparator}wallpapers');
    if (!wallpapersDir.existsSync()) {
      wallpapersDir.createSync(recursive: true);
    }

    final ext = _safeExtension(pickedPath);
    final fileName = 'wallpaper_${DateTime.now().millisecondsSinceEpoch}$ext';
    final destPath =
        '${wallpapersDir.path}${Platform.pathSeparator}$fileName';
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
}

class BackgroundPresets {
  static const List<String> wallpaperUrls = [];
}
