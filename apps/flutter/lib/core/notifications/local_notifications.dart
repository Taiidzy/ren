import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/providers/theme_settings.dart';
import 'package:ren/core/secure/secure_storage.dart';

class LocalNotifications {
  LocalNotifications._();

  static final LocalNotifications instance = LocalNotifications._();

  static const String _channelId = 'ren_messages';
  static const String _channelName = 'Messages';
  static const String _channelDescription = 'Chat message notifications';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> Function(int chatId)? _onOpenChat;

  void setOnOpenChat(Future<void> Function(int chatId)? handler) {
    _onOpenChat = handler;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const macosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
      macOS: macosInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            final chatIdDyn = decoded['chat_id'] ?? decoded['chatId'];
            final chatId = (chatIdDyn is int)
                ? chatIdDyn
                : int.tryParse('$chatIdDyn') ?? 0;
            if (chatId > 0) {
              final cb = _onOpenChat;
              if (cb != null) {
                await cb(chatId);
              }
            }
          }
        } catch (_) {
          // ignore
        }
      },
    );

    await _ensureChannel();
    await _requestPermissions();

    _initialized = true;
  }

  Future<void> _ensureChannel() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
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
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
      return;
    }

    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
    }
  }

  Future<void> showMessageNotification({
    required int chatId,
    required String title,
    required String body,
    String? avatarUrl,
    String? senderName,
  }) async {
    await initialize();

    final color = await _readAccentColor();

    final avatar = await _tryDownloadAvatar(
      avatarUrl: avatarUrl,
      senderName: senderName,
      chatId: chatId,
    );

    final avatarPath = avatar?.path;
    final avatarBytes = avatar?.bytes;

    final attachments = <DarwinNotificationAttachment>[];
    if (avatarPath != null && avatarPath.isNotEmpty) {
      final a = DarwinNotificationAttachment(avatarPath);
      attachments.add(a);
    }

    final AndroidBitmap<Object>? avatarBitmap =
        (avatarBytes != null && avatarBytes.isNotEmpty)
        ? ByteArrayAndroidBitmap(avatarBytes)
        : ((avatarPath != null && avatarPath.isNotEmpty)
              ? FilePathAndroidBitmap(avatarPath)
              : null);

    final StyleInformation? androidStyle = (avatarBitmap != null)
        ? BigPictureStyleInformation(
            avatarBitmap,
            largeIcon: avatarBitmap,
            contentTitle: title,
            summaryText: body,
          )
        : null;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        color: color,
        largeIcon: avatarBitmap,
        styleInformation: androidStyle,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        attachments: attachments,
      ),
    );

    // keep id stable per chat to collapse notifications
    final id = chatId.abs();

    final payload = jsonEncode({'chat_id': chatId});

    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<({String path, Uint8List bytes})?> _tryDownloadAvatar({
    required String? avatarUrl,
    required String? senderName,
    required int chatId,
  }) async {
    final url = avatarUrl?.trim();
    if (url == null || url.isEmpty) return null;

    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;

      final client = HttpClient();
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }

      final bytes = await consolidateHttpClientResponseBytes(res);
      if (bytes.isEmpty) return null;

      final dir = await getTemporaryDirectory();
      final safe = (senderName ?? 'user').replaceAll(
        RegExp(r'[^a-zA-Z0-9_\-]'),
        '_',
      );
      final path = '${dir.path}/notif_avatar_${chatId}_$safe.png';
      final f = File(path);
      await f.writeAsBytes(bytes, flush: true);
      return (path: path, bytes: bytes);
    } catch (_) {
      return null;
    }
  }

  Future<Color?> _readAccentColor() async {
    final schemeStr = await SecureStorage.readKey(Keys.themeColorScheme);
    final preset = _parseScheme(schemeStr) ?? AppColorSchemePreset.indigo;

    switch (preset) {
      case AppColorSchemePreset.auto:
        final backgroundValue = await SecureStorage.readKey(
          Keys.backgroundValue,
        );
        if (backgroundValue == null || backgroundValue.isEmpty) {
          return const Color(0xFF6366F1);
        }
        return _colorFromTextHash(backgroundValue);
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

  Color _colorFromTextHash(String input) {
    var hash = 0;
    for (final unit in input.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.68, 0.52).toColor();
  }

  AppColorSchemePreset? _parseScheme(String? v) {
    if (v == null || v.isEmpty) return null;
    for (final scheme in AppColorSchemePreset.values) {
      if (scheme.name == v) return scheme;
    }
    return null;
  }
}
