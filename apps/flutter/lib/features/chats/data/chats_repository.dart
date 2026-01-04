import 'dart:convert';

import 'package:flutter/foundation.dart';
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

    final ciphertext = (payload['ciphertext'] as String?)?.trim();
    final nonce = (payload['nonce'] as String?)?.trim();
    if (ciphertext == null || nonce == null) {
      debugPrint('decrypt: missing ciphertext/nonce');
      return '[encrypted]';
    }

    final priv = myPrivateKeyB64?.trim();
    if (priv == null || priv.isEmpty) {
      debugPrint('decrypt: missing private key');
      return '[encrypted]';
    }

    final envMap = (envelopes is Map) ? envelopes : null;
    if (envMap == null) {
      return '[encrypted]';
    }

    // envelopes может приходить как Map<int, ...> или Map<String, ...>
    dynamic envDyn = envMap['$myUserId'];
    envDyn ??= envMap[myUserId];
    final env = envDyn is Map ? envDyn : null;
    if (env == null) {
      debugPrint('decrypt: no envelope for user=$myUserId keys=${envMap.keys.toList()}');
      return '[encrypted]';
    }

    String? asString(dynamic v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;

    final wrapped = asString(env['key']) ?? asString(env['wrapped']);
    final eph = asString(env['ephem_pub_key']) ?? asString(env['ephemeral_public_key']);
    final wrapNonce = asString(env['iv']) ?? asString(env['nonce']);

    if (wrapped == null || eph == null || wrapNonce == null) {
      debugPrint('decrypt: missing wrapped/eph/nonce in envelope for user=$myUserId');
      return '[encrypted]';
    }

    final msgKey = renSdk.unwrapSymmetricKey(wrapped, eph, wrapNonce, priv);
    if (msgKey == null) {
      debugPrint(
        'decrypt: unwrapSymmetricKey failed (user=$myUserId) '
        'privLen=${priv.length} wrappedLen=${wrapped.length} ephLen=${eph.length}',
      );
      return '[encrypted]';
    }

    final decrypted = renSdk.decryptMessage(ciphertext, nonce, msgKey);
    if (decrypted == null) {
      debugPrint('decrypt: decryptMessage failed');
    }
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

  Future<Map<String, dynamic>> buildEncryptedWsMessage({
    required int chatId,
    required int peerId,
    required String plaintext,
  }) async {
    final myUserIdStr = await SecureStorage.readKey(Keys.UserId);
    final myUserId = int.tryParse(myUserIdStr ?? '') ?? 0;
    final myPrivateKeyB64 = (await SecureStorage.readKey(Keys.PrivateKey))?.trim();
    final myPublicKeyB64 = (await SecureStorage.readKey(Keys.PublicKey))?.trim();

    if (myUserId == 0) {
      throw Exception('Не найден userId');
    }
    if (myPrivateKeyB64 == null || myPrivateKeyB64.isEmpty) {
      throw Exception('Не найден приватный ключ');
    }
    if (myPublicKeyB64 == null || myPublicKeyB64.isEmpty) {
      throw Exception('Не найден публичный ключ');
    }

    final peerPublicKeyB64 = (await api.getPublicKey(peerId)).trim();

    final msgKeyB64 = renSdk.generateMessageKey().trim();
    final enc = renSdk.encryptMessage(plaintext, msgKeyB64);
    if (enc == null) {
      throw Exception('Не удалось зашифровать сообщение');
    }

    final wrappedForMe = renSdk.wrapSymmetricKey(msgKeyB64, myPublicKeyB64);
    final wrappedForPeer = renSdk.wrapSymmetricKey(msgKeyB64, peerPublicKeyB64);
    if (wrappedForMe == null || wrappedForPeer == null) {
      throw Exception('Не удалось сформировать envelopes');
    }

    // self-check: мы обязаны уметь развернуть свой же envelope
    final selfWrapped = (wrappedForMe['wrapped'] ?? '').trim();
    final selfEph = (wrappedForMe['ephemeral_public_key'] ?? '').trim();
    final selfNonce = (wrappedForMe['nonce'] ?? '').trim();
    final selfUnwrapped = renSdk.unwrapSymmetricKey(
      selfWrapped,
      selfEph,
      selfNonce,
      myPrivateKeyB64,
    );
    if (selfUnwrapped == null || selfUnwrapped.isEmpty) {
      debugPrint(
        'e2ee self-check failed: myUserId=$myUserId '
        'privLen=${myPrivateKeyB64.length} pubLen=${myPublicKeyB64.length} '
        'wrappedLen=${selfWrapped.length} ephLen=${selfEph.length}',
      );
      throw Exception('Ошибка E2EE: не удалось развернуть собственный envelope (ключи не совпадают)');
    }

    Map<String, dynamic> env(String userId, Map<String, String> w) {
      return {
        'key': w['wrapped'],
        'ephem_pub_key': w['ephemeral_public_key'],
        'iv': w['nonce'],
      };
    }

    final envelopes = <String, dynamic>{
      '$myUserId': env('$myUserId', wrappedForMe),
      '$peerId': env('$peerId', wrappedForPeer),
    };

    final messageJson = jsonEncode({
      'ciphertext': enc['ciphertext'],
      'nonce': enc['nonce'],
    });

    return {
      'chat_id': chatId,
      'message': messageJson,
      'message_type': 'text',
      'envelopes': envelopes,
      'metadata': null,
    };
  }

  Future<String> decryptIncomingWsMessage({
    required Map<String, dynamic> message,
  }) async {
    final myUserIdStr = await SecureStorage.readKey(Keys.UserId);
    final myUserId = int.tryParse(myUserIdStr ?? '') ?? 0;
    final myPrivateKeyB64 = await SecureStorage.readKey(Keys.PrivateKey);

    final encrypted = message['message'] as String? ?? '';
    final envelopes = message['envelopes'];

    return _tryDecryptMessage(
      encrypted: encrypted,
      envelopes: envelopes,
      myUserId: myUserId,
      myPrivateKeyB64: myPrivateKeyB64,
    );
  }

  String _avatarUrl(String avatarPath) {
    final p = avatarPath.trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    final normalized = p.startsWith('/') ? p.substring(1) : p;
    return '${Apiurl.api}/avatars/$normalized';
  }
}
