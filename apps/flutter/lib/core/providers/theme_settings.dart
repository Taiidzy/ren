import 'package:flutter/material.dart';

import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';

enum AppColorSchemePreset {
  indigo,
  emerald,
  rose,
  orange,
  cyan,
}

class ThemeSettings extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  AppColorSchemePreset _colorScheme = AppColorSchemePreset.indigo;

  int _mutationId = 0;

  ThemeMode get themeMode => _themeMode;
  AppColorSchemePreset get colorScheme => _colorScheme;

  ThemeSettings() {
    _load();
  }

  Future<void> _load() async {
    final int loadMutationId = _mutationId;
    final themeModeStr = await SecureStorage.readKey(Keys.themeMode);
    final schemeStr = await SecureStorage.readKey(Keys.themeColorScheme);

    if (loadMutationId != _mutationId) {
      return;
    }

    final parsedThemeMode = _parseThemeMode(themeModeStr);
    final parsedScheme = _parseScheme(schemeStr);

    var changed = false;
    if (parsedThemeMode != null && parsedThemeMode != _themeMode) {
      _themeMode = parsedThemeMode;
      changed = true;
    }
    if (parsedScheme != null && parsedScheme != _colorScheme) {
      _colorScheme = parsedScheme;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _mutationId++;
    _themeMode = mode;
    notifyListeners();

    SecureStorage.writeKey(Keys.themeMode, _themeMode.name);
  }

  void setColorScheme(AppColorSchemePreset preset) {
    if (preset == _colorScheme) return;
    _mutationId++;
    _colorScheme = preset;
    notifyListeners();

    SecureStorage.writeKey(Keys.themeColorScheme, _colorScheme.name);
  }

  ThemeMode? _parseThemeMode(String? v) {
    if (v == null || v.isEmpty) return null;
    for (final mode in ThemeMode.values) {
      if (mode.name == v) return mode;
    }
    return null;
  }

  AppColorSchemePreset? _parseScheme(String? v) {
    if (v == null || v.isEmpty) return null;
    for (final scheme in AppColorSchemePreset.values) {
      if (scheme.name == v) return scheme;
    }
    return null;
  }
}
