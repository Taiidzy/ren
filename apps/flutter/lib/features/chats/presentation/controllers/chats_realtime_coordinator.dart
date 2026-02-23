import 'dart:async';

import 'package:ren/core/realtime/realtime_client.dart';
import 'package:ren/features/chats/domain/chat_models.dart';

class ChatsRealtimeCoordinator {
  final RealtimeClient _client;

  StreamSubscription<RealtimeEvent>? _subscription;

  ChatsRealtimeCoordinator(this._client);

  Future<void> ensureConnected({
    required List<ChatPreview> chats,
    required FutureOr<void> Function(RealtimeEvent event) onEvent,
  }) async {
    if (!_client.isConnected) {
      await _client.connect();
    }

    final contacts = <int>[];
    for (final chat in chats) {
      final peerId = chat.peerId;
      if (peerId != null && peerId > 0) {
        contacts.add(peerId);
      }
    }
    _client.setContacts(contacts);

    _subscription ??= _client.events.listen((event) {
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
