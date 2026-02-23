import 'dart:async';

import 'package:ren/core/realtime/realtime_client.dart';

class ChatPageRealtimeCoordinator {
  final RealtimeClient client;
  StreamSubscription<RealtimeEvent>? _subscription;

  ChatPageRealtimeCoordinator(this.client);

  Future<void> ensureConnected({
    required int chatId,
    required bool isPrivateChat,
    required int peerId,
    required FutureOr<void> Function(RealtimeEvent event) onEvent,
  }) async {
    if (!client.isConnected) {
      await client.connect();
    }

    if (isPrivateChat && peerId > 0) {
      client.addContacts([peerId]);
    }

    client.joinChat(chatId);

    _subscription ??= client.events.listen((event) {
      final result = onEvent(event);
      if (result is Future<void>) {
        unawaited(result);
      }
    });
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
