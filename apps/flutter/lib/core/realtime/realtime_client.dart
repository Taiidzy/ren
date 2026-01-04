import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';

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
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  final _events = StreamController<RealtimeEvent>.broadcast();

  bool get isConnected => _channel != null;

  Stream<RealtimeEvent> get events => _events.stream;

  Future<void> connect() async {
    if (_channel != null) return;

    final token = await SecureStorage.readKey(Keys.Token);
    if (token == null || token.isEmpty) {
      throw Exception('Нет токена авторизации');
    }

    final base = Uri.parse(Apiurl.ws);
    if (!(base.scheme == 'ws' || base.scheme == 'wss')) {
      throw Exception('Apiurl.ws должен начинаться с ws:// или wss://');
    }

    final uri = base.replace(
      path: '/ws',
      queryParameters: {
        'token': token,
      },
    );
    debugPrint('WS connect: $uri');

    final ch = IOWebSocketChannel.connect(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    _channel = ch;

    _sub = ch.stream.listen(
      (event) {
        if (event is String) {
          try {
            final json = jsonDecode(event);
            if (json is Map<String, dynamic>) {
              _events.add(RealtimeEvent.fromJson(json));
            }
          } catch (_) {
            // ignore non-json
          }
        }
      },
      onError: (e) {
        debugPrint('WS error: $e');
      },
      onDone: () {
        _channel = null;
        _sub?.cancel();
        _sub = null;
      },
    );
  }

  Future<void> disconnect() async {
    _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _events.close();
  }

  void _send(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null) return;
    ch.sink.add(jsonEncode(payload));
  }

  void init({required List<int> contacts}) {
    _send({'type': 'init', 'contacts': contacts});
  }

  void joinChat(int chatId) {
    _send({'type': 'join_chat', 'chat_id': chatId});
  }

  void leaveChat(int chatId) {
    _send({'type': 'leave_chat', 'chat_id': chatId});
  }

  void typing(int chatId, bool isTyping) {
    _send({'type': 'typing', 'chat_id': chatId, 'is_typing': isTyping});
  }

  void sendMessage({
    required int chatId,
    required String message,
    required Map<String, dynamic>? envelopes,
    String? messageType,
    List<dynamic>? metadata,
  }) {
    _send({
      'type': 'send_message',
      'chat_id': chatId,
      'message': message,
      'message_type': messageType,
      'envelopes': envelopes,
      'metadata': metadata,
    });
  }
}
