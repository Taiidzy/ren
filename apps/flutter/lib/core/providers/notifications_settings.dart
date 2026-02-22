import 'package:flutter/material.dart';

import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';

class NotificationsSettings extends ChangeNotifier {
  bool _hapticEnabled = true;
  bool _inAppBannersEnabled = true;
  bool _inAppSoundEnabled = true;
  int _mutationId = 0;

  bool get hapticEnabled => _hapticEnabled;
  bool get inAppBannersEnabled => _inAppBannersEnabled;
  bool get inAppSoundEnabled => _inAppSoundEnabled;

  NotificationsSettings() {
    _load();
  }

  Future<void> _load() async {
    final loadMutationId = _mutationId;
    final rawHaptic = await SecureStorage.readKey(
      Keys.notificationsHapticEnabled,
    );
    final rawBanners = await SecureStorage.readKey(
      Keys.notificationsInAppBannersEnabled,
    );
    final rawSound = await SecureStorage.readKey(
      Keys.notificationsInAppSoundEnabled,
    );
    if (loadMutationId != _mutationId) return;

    var changed = false;
    final parsedHaptic = _parseBool(rawHaptic);
    if (parsedHaptic != null && parsedHaptic != _hapticEnabled) {
      _hapticEnabled = parsedHaptic;
      changed = true;
    }
    final parsedBanners = _parseBool(rawBanners);
    if (parsedBanners != null && parsedBanners != _inAppBannersEnabled) {
      _inAppBannersEnabled = parsedBanners;
      changed = true;
    }
    final parsedSound = _parseBool(rawSound);
    if (parsedSound != null && parsedSound != _inAppSoundEnabled) {
      _inAppSoundEnabled = parsedSound;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> setHapticEnabled(bool value) async {
    if (value == _hapticEnabled) return;
    _mutationId++;
    _hapticEnabled = value;
    notifyListeners();
    await SecureStorage.writeKey(
      Keys.notificationsHapticEnabled,
      value ? '1' : '0',
    );
  }

  Future<void> setInAppBannersEnabled(bool value) async {
    if (value == _inAppBannersEnabled) return;
    _mutationId++;
    _inAppBannersEnabled = value;
    notifyListeners();
    await SecureStorage.writeKey(
      Keys.notificationsInAppBannersEnabled,
      value ? '1' : '0',
    );
  }

  Future<void> setInAppSoundEnabled(bool value) async {
    if (value == _inAppSoundEnabled) return;
    _mutationId++;
    _inAppSoundEnabled = value;
    notifyListeners();
    await SecureStorage.writeKey(
      Keys.notificationsInAppSoundEnabled,
      value ? '1' : '0',
    );
  }

  bool? _parseBool(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final v = raw.trim().toLowerCase();
    if (v == '1' || v == 'true' || v == 'yes' || v == 'on') return true;
    if (v == '0' || v == 'false' || v == 'no' || v == 'off') return false;
    return null;
  }
}
