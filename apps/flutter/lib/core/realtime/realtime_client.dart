import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/sdk/ren_sdk.dart';
import 'package:ren/core/secure/secure_storage.dart';

Future<Map<String, dynamic>?> _decodeWsEventJson(String raw) async {
  try {
    final json = jsonDecode(raw);
    if (json is Map<String, dynamic>) return json;
    return null;
  } catch (_) {
    return null;
  }
}

class RealtimeEvent {
  final String type;
  final Map<String, dynamic> data;

  RealtimeEvent(this.type, this.data);

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    return RealtimeEvent(type, json);
  }
}

class RealtimeClient {
  static const Duration _reconnectMinDelay = Duration(seconds: 1);
  static const Duration _reconnectMaxDelay = Duration(seconds: 20);

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;

  final _events = StreamController<RealtimeEvent>.broadcast();

  final Set<int> _contacts = <int>{};
  final Set<int> _joinedChats = <int>{};
  final List<Map<String, dynamic>> _pendingMessages = <Map<String, dynamic>>[];

  bool _isConnecting = false;
  bool _manualDisconnect = false;
  bool _hasConnectedBefore = false;
  Duration _currentReconnectDelay = _reconnectMinDelay;

  bool get isConnected => _channel != null;

  Stream<RealtimeEvent> get events => _events.stream;

  Future<void> connect() async {
    if (_channel != null || _isConnecting) return;

    final token = await SecureStorage.readKey(Keys.token);
    if (token == null || token.isEmpty) {
      throw Exception('Нет токена авторизации');
    }

    _manualDisconnect = false;
    _isConnecting = true;
    _cancelReconnectTimer();

    try {
      final base = Uri.parse(Apiurl.ws);
      if (!(base.scheme == 'ws' || base.scheme == 'wss')) {
        throw Exception('Apiurl.ws должен начинаться с ws:// или wss://');
      }

      // Do not place bearer tokens in URL query to avoid leaks in logs/proxies.
      final uri = base.replace(path: '/ws');

      final sdkFingerprint = currentSdkFingerprint();
      final ch = IOWebSocketChannel.connect(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          if (sdkFingerprint.isNotEmpty) 'X-SDK-Fingerprint': sdkFingerprint,
        },
      );

      _channel = ch;

      await ch.ready;

      if (!identical(_channel, ch)) {
        return;
      }

      _currentReconnectDelay = _reconnectMinDelay;
      _sub = ch.stream.listen(
        (event) async {
          if (event is! String) return;

          Map<String, dynamic>? json;
          if (!kIsWeb && event.length > 4096) {
            json = await compute(_decodeWsEventJson, event);
          } else {
            json = await _decodeWsEventJson(event);
          }

          if (json != null) {
            _events.add(RealtimeEvent.fromJson(json));
          }
        },
        onError: (e) {
          debugPrint('WS error: $e');
          _handleSocketClosed();
        },
        onDone: _handleSocketClosed,
        cancelOnError: true,
      );

      _flushState();
      _events.add(
        RealtimeEvent('connection', {
          'type': 'connection',
          'state': 'connected',
          'reconnected': _hasConnectedBefore,
        }),
      );
      _hasConnectedBefore = true;
    } catch (e) {
      _channel = null;
      _sub?.cancel();
      _sub = null;
      if (!_manualDisconnect) {
        _scheduleReconnect();
      }
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _cancelReconnectTimer();
    _pendingMessages.clear();

    final localSub = _sub;
    _sub = null;
    await localSub?.cancel();

    final ch = _channel;
    _channel = null;
    await ch?.sink.close();
  }

  void dispose() {
    _manualDisconnect = true;
    _cancelReconnectTimer();
    disconnect();
    _events.close();
  }

  void _handleSocketClosed() {
    _sub?.cancel();
    _sub = null;
    _channel = null;
    if (!_manualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _reconnectTimer != null) return;
    _reconnectTimer = Timer(_currentReconnectDelay, () async {
      _reconnectTimer = null;
      final nextMs = (_currentReconnectDelay.inMilliseconds * 2).clamp(
        _reconnectMinDelay.inMilliseconds,
        _reconnectMaxDelay.inMilliseconds,
      );
      _currentReconnectDelay = Duration(milliseconds: nextMs);
      try {
        await connect();
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _send(Map<String, dynamic> payload, {bool queueIfDisconnected = true}) {
    final ch = _channel;
    if (ch != null) {
      ch.sink.add(jsonEncode(payload));
      return;
    }

    if (queueIfDisconnected) {
      _pendingMessages.add(payload);
      unawaited(connect());
    }
  }

  void _flushState() {
    _send({
      'type': 'init',
      'contacts': _contacts.toList(growable: false),
    }, queueIfDisconnected: false);

    for (final chatId in _joinedChats) {
      _send({
        'type': 'join_chat',
        'chat_id': chatId,
      }, queueIfDisconnected: false);
    }

    if (_pendingMessages.isNotEmpty) {
      final pending = List<Map<String, dynamic>>.from(_pendingMessages);
      _pendingMessages.clear();
      for (final payload in pending) {
        _send(payload, queueIfDisconnected: false);
      }
    }
  }

  void setContacts(Iterable<int> contacts) {
    _contacts
      ..clear()
      ..addAll(contacts.where((id) => id > 0));

    _send({'type': 'init', 'contacts': _contacts.toList(growable: false)});
  }

  void addContacts(Iterable<int> contacts) {
    var changed = false;
    for (final id in contacts) {
      if (id <= 0) continue;
      changed = _contacts.add(id) || changed;
    }

    if (changed) {
      _send({'type': 'init', 'contacts': _contacts.toList(growable: false)});
    }
  }

  void init({required List<int> contacts}) {
    addContacts(contacts);
  }

  void joinChat(int chatId) {
    if (chatId <= 0) return;
    if (_joinedChats.add(chatId)) {
      _send({'type': 'join_chat', 'chat_id': chatId});
    }
  }

  void leaveChat(int chatId) {
    if (_joinedChats.remove(chatId)) {
      _send({'type': 'leave_chat', 'chat_id': chatId});
    }
  }

  void typing(int chatId, bool isTyping) {
    _send({
      'type': 'typing',
      'chat_id': chatId,
      'is_typing': isTyping,
    }, queueIfDisconnected: false);
  }

  void sendMessage({
    required int chatId,
    required String message,
    required Map<String, dynamic>? envelopes,
    String wsType = 'send_message',
    String? messageType,
    List<dynamic>? metadata,
    int? replyToMessageId,
  }) {
    _send({
      'type': wsType,
      'chat_id': chatId,
      'message': message,
      'message_type': messageType,
      'envelopes': envelopes,
      'metadata': metadata,
      'reply_to_message_id': replyToMessageId,
    });
  }

  void deleteMessage({required int chatId, required int messageId}) {
    _send({
      'type': 'delete_message',
      'chat_id': chatId,
      'message_id': messageId,
    });
  }

  void forwardMessage({
    required int fromChatId,
    required int messageId,
    required int toChatId,
    required String message,
    required Map<String, dynamic>? envelopes,
    String? messageType,
    List<dynamic>? metadata,
  }) {
    _send({
      'type': 'forward_message',
      'from_chat_id': fromChatId,
      'message_id': messageId,
      'to_chat_id': toChatId,
      'message': message,
      'message_type': messageType,
      'envelopes': envelopes,
      'metadata': metadata,
    });
  }

  void editMessage({
    required int chatId,
    required int messageId,
    required String message,
    required Map<String, dynamic>? envelopes,
    String? messageType,
    List<dynamic>? metadata,
  }) {
    _send({
      'type': 'edit_message',
      'chat_id': chatId,
      'message_id': messageId,
      'message': message,
      'message_type': messageType,
      'envelopes': envelopes,
      'metadata': metadata,
    });
  }
}
