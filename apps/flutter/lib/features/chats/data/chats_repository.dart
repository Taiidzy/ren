import 'dart:convert';

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/sdk/ren_sdk.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/features/chats/data/chats_api.dart';
import 'package:ren/features/chats/domain/chat_models.dart';

class ChatsRepository {
  final ChatsApi api;
  final RenSdk renSdk;

  ChatsRepository(this.api, this.renSdk);

  Future<List<ChatPreview>> fetchChats() async {
    final raw = await api.listChats();
    final items = <ChatPreview>[];

    for (final it in raw) {
      final m = (it as Map).cast<String, dynamic>();
      final id = (m['id'] is int) ? m['id'] as int : int.tryParse('${m['id']}') ?? 0;
      final peerId = (m['peer_id'] is int)
          ? m['peer_id'] as int
          : int.tryParse('${m['peer_id']}');
      final peerUsername = (m['peer_username'] as String?) ?? '';
      final peerAvatar = (m['peer_avatar'] as String?) ?? '';
      final updatedAtStr = (m['updated_at'] as String?) ?? '';

      final updatedAt = DateTime.tryParse(updatedAtStr) ?? DateTime.now();

      final user = ChatUser(
        id: (peerId ?? 0).toString(),
        name: peerUsername.isNotEmpty ? peerUsername : 'User',
        avatarUrl: _avatarUrl(peerAvatar),
        isOnline: false,
      );

      items.add(
        ChatPreview(
          id: id.toString(),
          peerId: peerId,
          kind: (m['kind'] as String?) ?? 'private',
          user: user,
          lastMessage: '',
          lastMessageAt: updatedAt,
        ),
      );
    }

    return items;
  }

  Future<List<ChatUser>> favorites() async {
    final chats = await fetchChats();
    final out = <ChatUser>[];
    for (final c in chats.take(8)) {
      out.add(c.user);
    }
    return out;
  }

  Future<List<ChatMessage>> fetchMessages(int chatId) async {
    final raw = await api.getMessages(chatId);

    final myUserIdStr = await SecureStorage.readKey(Keys.UserId);
    final myUserId = int.tryParse(myUserIdStr ?? '') ?? 0;

    final privateKey = await SecureStorage.readKey(Keys.PrivateKey);

    final out = <ChatMessage>[];

    for (final it in raw) {
      final m = (it as Map).cast<String, dynamic>();
      final messageId = (m['id'] is int) ? m['id'] as int : int.tryParse('${m['id']}') ?? 0;
      final senderId = (m['sender_id'] is int)
          ? m['sender_id'] as int
          : int.tryParse('${m['sender_id']}') ?? 0;

      final createdAtStr = (m['created_at'] as String?) ?? '';
      final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();

      final encrypted = (m['message'] as String?) ?? '';

      final text = await _tryDecryptMessage(
        encrypted: encrypted,
        envelopes: m['envelopes'],
        myUserId: myUserId,
        myPrivateKeyB64: privateKey,
      );

      out.add(
        ChatMessage(
          id: messageId.toString(),
          chatId: chatId.toString(),
          isMe: senderId == myUserId,
          text: text,
          sentAt: createdAt,
        ),
      );
    }

    return out;
  }

  Future<String> _tryDecryptMessage({
    required String encrypted,
    required dynamic envelopes,
    required int myUserId,
    required String? myPrivateKeyB64,
  }) async {
    if (encrypted.isEmpty) return '';

    Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(encrypted) as Map<String, dynamic>;
    } catch (_) {
      return '[encrypted]';
    }

    final ciphertext = payload['ciphertext'] as String?;
    final nonce = payload['nonce'] as String?;
    if (ciphertext == null || nonce == null) {
      return '[encrypted]';
    }

    if (myPrivateKeyB64 == null || myPrivateKeyB64.isEmpty) {
      return '[encrypted]';
    }

    final envMap = (envelopes is Map) ? envelopes.cast<String, dynamic>() : null;
    final env = envMap?['$myUserId'] as Map?;
    if (env == null) {
      return '[encrypted]';
    }

    final wrapped = env['key'] as String?;
    final eph = env['ephem_pub_key'] as String?;
    final iv = env['iv'] as String?;

    if (wrapped == null || eph == null || iv == null) {
      return '[encrypted]';
    }

    final msgKey = renSdk.unwrapSymmetricKey(wrapped, eph, myPrivateKeyB64);
    if (msgKey == null) {
      return '[encrypted]';
    }

    final decrypted = renSdk.decryptMessage(ciphertext, nonce, msgKey);
    return decrypted ?? '[encrypted]';
  }

  Future<ChatPreview> createPrivateChat(int peerId) async {
    final myUserIdStr = await SecureStorage.readKey(Keys.UserId);
    final myUserId = int.tryParse(myUserIdStr ?? '') ?? 0;

    final json = await api.createChat(
      kind: 'private',
      userIds: [myUserId, peerId],
    );

    final id = (json['id'] is int) ? json['id'] as int : int.tryParse('${json['id']}') ?? 0;

    return ChatPreview(
      id: id.toString(),
      peerId: peerId,
      kind: (json['kind'] as String?) ?? 'private',
      user: ChatUser(
        id: peerId.toString(),
        name: (json['peer_username'] as String?) ?? 'User',
        avatarUrl: _avatarUrl((json['peer_avatar'] as String?) ?? ''),
        isOnline: false,
      ),
      lastMessage: '',
      lastMessageAt: DateTime.now(),
    );
  }

  Future<void> deleteChat(int chatId, {bool forAll = false}) async {
    await api.deleteChat(chatId, forAll: forAll);
  }

  String _avatarUrl(String avatarPath) {
    final p = avatarPath.trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    final normalized = p.startsWith('/') ? p.substring(1) : p;
    return '${Apiurl.api}/avatars/$normalized';
  }
}
