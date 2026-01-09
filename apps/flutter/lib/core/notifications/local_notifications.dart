import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/providers/theme_settings.dart';
import 'package:ren/core/secure/secure_storage.dart';

class LocalNotifications {
  LocalNotifications._();

  static final LocalNotifications instance = LocalNotifications._();

  static const String _channelId = 'ren_messages';
  static const String _channelName = 'Messages';
  static const String _channelDescription = 'Chat message notifications';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(initSettings);

    await _ensureChannel();
    await _requestPermissions();

    _initialized = true;
  }

  Future<void> _ensureChannel() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );

    await android.createNotificationChannel(channel);
  }

  Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      final ios =
          _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return;
    }

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    }
  }

  Future<void> showMessageNotification({
    required int chatId,
    required String title,
    required String body,
  }) async {
    await initialize();

    final color = await _readAccentColor();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        color: color,
        enableVibration: true,
        playSound: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    // keep id stable per chat to collapse notifications
    final id = chatId.abs();

    await _plugin.show(
      id,
      title,
      body,
      details,
    );
  }

  Future<Color?> _readAccentColor() async {
    final schemeStr = await SecureStorage.readKey(Keys.ThemeColorScheme);
    final preset = _parseScheme(schemeStr) ?? AppColorSchemePreset.indigo;

    switch (preset) {
      case AppColorSchemePreset.indigo:
        return const Color(0xFF6366F1);
      case AppColorSchemePreset.emerald:
        return const Color(0xFF10B981);
      case AppColorSchemePreset.rose:
        return const Color(0xFFF43F5E);
      case AppColorSchemePreset.orange:
        return const Color(0xFFF97316);
      case AppColorSchemePreset.cyan:
        return const Color(0xFF06B6D4);
    }
  }

  AppColorSchemePreset? _parseScheme(String? v) {
    if (v == null || v.isEmpty) return null;
    for (final scheme in AppColorSchemePreset.values) {
      if (scheme.name == v) return scheme;
    }
    return null;
  }
}
