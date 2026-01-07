import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/sdk/ren_sdk.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/features/chats/data/chats_api.dart';
import 'package:ren/features/chats/domain/chat_models.dart';

class OutgoingAttachment {
  final List<int> bytes;
  final String filename;
  final String mimetype;

  const OutgoingAttachment({
    required this.bytes,
    required this.filename,
    required this.mimetype,
  });
}

class ChatsRepository {
  final ChatsApi api;
  final RenSdk renSdk;

  final Map<int, Uint8List> _ciphertextMemoryCache = <int, Uint8List>{};
  final Map<int, Future<Uint8List>> _ciphertextInFlight = <int, Future<Uint8List>>{};

  ChatsRepository(this.api, this.renSdk);

  Future<Uint8List> _getCiphertextBytes(int fileId) async {
    final cached = _ciphertextMemoryCache[fileId];
    if (cached != null) {
      return cached;
    }

    final inFlight = _ciphertextInFlight[fileId];
    if (inFlight != null) {
      return inFlight;
    }

    final future = () async {
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory('${dir.path}/ren_ciphertext_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final cacheFile = File('${cacheDir.path}/$fileId.bin');

      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        _ciphertextMemoryCache[fileId] = bytes;
        return bytes;
      }

      final bytes = await api.downloadMedia(fileId);
      _ciphertextMemoryCache[fileId] = bytes;
      try {
        await cacheFile.writeAsBytes(bytes, flush: true);
      } catch (_) {
        // ignore cache write errors
      }
      return bytes;
    }();

    _ciphertextInFlight[fileId] = future;
    try {
      return await future;
    } finally {
      _ciphertextInFlight.remove(fileId);
    }
  }

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

  Future<List<ChatMessage>> fetchMessages(
    int chatId, {
    int? limit,
    int? beforeId,
    int? afterId,
  }) async {
    final raw = await api.getMessages(
      chatId,
      limit: limit,
      beforeId: beforeId,
      afterId: afterId,
    );

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

      final replyDyn = m['reply_to_message_id'] ?? m['replyToMessageId'];
      final replyId = (replyDyn is int)
          ? replyDyn
          : int.tryParse('${replyDyn ?? ''}');

      final createdAtStr = (m['created_at'] as String?) ?? '';
      final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();

      final encrypted = (m['message'] as String?) ?? '';

      final decrypted = await _tryDecryptMessageAndKey(
        encrypted: encrypted,
        envelopes: m['envelopes'],
        myUserId: myUserId,
        myPrivateKeyB64: privateKey,
      );

      final msgKey = decrypted.key;
      final attachments = await _tryDecryptAttachments(
        metadata: m['metadata'],
        msgKeyB64: msgKey,
      );

      out.add(
        ChatMessage(
          id: messageId.toString(),
          chatId: chatId.toString(),
          isMe: senderId == myUserId,
          text: decrypted.text,
          attachments: attachments,
          sentAt: createdAt,
          replyToMessageId: (replyId != null && replyId > 0) ? replyId.toString() : null,
        ),
      );
    }

    return out;
  }

  Future<List<ChatAttachment>> _tryDecryptAttachments({
    required dynamic metadata,
    required String? msgKeyB64,
  }) async {
    if (metadata is! List) return const [];
    final key = msgKeyB64?.trim();
    if (key == null || key.isEmpty) return const [];

    final out = <ChatAttachment>[];

    for (final item in metadata) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final fileIdDyn = m['file_id'];
      final encFile = (m['enc_file'] as String?)?.trim();
      final nonce = (m['nonce'] as String?)?.trim();
      final filename = (m['filename'] as String?) ?? 'file';
      final mimetype = (m['mimetype'] as String?) ?? 'application/octet-stream';
      final size = (m['size'] is int)
          ? m['size'] as int
          : int.tryParse('${m['size']}') ?? 0;

      if (nonce == null || nonce.isEmpty) {
        continue;
      }

      String? ciphertextB64;

      // New mode: ciphertext stored on server, referenced by file_id
      int? fileId;
      if (fileIdDyn is int) {
        fileId = fileIdDyn;
      } else if (fileIdDyn is String) {
        fileId = int.tryParse(fileIdDyn);
      }
      if (fileId != null && fileId > 0) {
        try {
          final ciphertextBytes = await _getCiphertextBytes(fileId);
          ciphertextB64 = base64Encode(ciphertextBytes);
        } catch (e) {
          debugPrint('download media failed fileId=$fileId err=$e');
          continue;
        }
      } else if (encFile != null && encFile.isNotEmpty) {
        // Legacy mode: ciphertext inline in metadata
        ciphertextB64 = encFile;
      }

      if (ciphertextB64 == null || ciphertextB64.isEmpty) {
        continue;
      }

      final bytes = await renSdk.decryptFileBytes(ciphertextB64, nonce, key);
      if (bytes == null) continue;

      final dir = await getTemporaryDirectory();
      final safeName = filename.isNotEmpty
          ? filename
          : 'file_${DateTime.now().millisecondsSinceEpoch}';
      final path = '${dir.path}/$safeName';
      final f = File(path);
      await f.writeAsBytes(bytes, flush: true);

      out.add(
        ChatAttachment(
          localPath: path,
          filename: filename,
          mimetype: mimetype,
          size: size,
        ),
      );
    }

    return out;
  }

  ({String text, String? key}) _decryptMessageWithKey({
    required String encrypted,
    required dynamic envelopes,
    required int myUserId,
    required String? myPrivateKeyB64,
  }) {
    if (encrypted.isEmpty) return (text: '', key: null);

    Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(encrypted) as Map<String, dynamic>;
    } catch (_) {
      return (text: '[encrypted]', key: null);
    }

    final ciphertext = (payload['ciphertext'] as String?)?.trim();
    final nonce = (payload['nonce'] as String?)?.trim();
    if (ciphertext == null || nonce == null) {
      debugPrint('decrypt: missing ciphertext/nonce');
      return (text: '[encrypted]', key: null);
    }

    final priv = myPrivateKeyB64?.trim();
    if (priv == null || priv.isEmpty) {
      debugPrint('decrypt: missing private key');
      return (text: '[encrypted]', key: null);
    }

    final envMap = (envelopes is Map) ? envelopes : null;
    if (envMap == null) {
      return (text: '[encrypted]', key: null);
    }

    dynamic envDyn = envMap['$myUserId'];
    envDyn ??= envMap[myUserId];
    final env = envDyn is Map ? envDyn : null;
    if (env == null) {
      return (text: '[encrypted]', key: null);
    }

    String? asString(dynamic v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;

    final wrapped = asString(env['key']) ?? asString(env['wrapped']);
    final eph = asString(env['ephem_pub_key']) ?? asString(env['ephemeral_public_key']);
    final wrapNonce = asString(env['iv']) ?? asString(env['nonce']);

    if (wrapped == null || eph == null || wrapNonce == null) {
      debugPrint('decrypt: missing wrapped/eph/nonce in envelope for user=$myUserId');
      return (text: '[encrypted]', key: null);
    }

    final msgKey = renSdk.unwrapSymmetricKey(wrapped, eph, wrapNonce, priv);
    if (msgKey == null) {
      return (text: '[encrypted]', key: null);
    }

    final decrypted = renSdk.decryptMessage(ciphertext, nonce, msgKey);
    if (decrypted == null) {
      debugPrint('decrypt: decryptMessage failed');
    }
    return (text: decrypted ?? '[encrypted]', key: msgKey);
  }

  Future<({String text, String? key})> _tryDecryptMessageAndKey({
    required String encrypted,
    required dynamic envelopes,
    required int myUserId,
    required String? myPrivateKeyB64,
  }) async {
    return _decryptMessageWithKey(
      encrypted: encrypted,
      envelopes: envelopes,
      myUserId: myUserId,
      myPrivateKeyB64: myPrivateKeyB64,
    );
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

  Future<Map<String, dynamic>> buildEncryptedWsImageMessage({
    required int chatId,
    required int peerId,
    required Uint8List fileBytes,
    required String filename,
    required String mimetype,
    required String caption,
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
    final encMsg = renSdk.encryptMessage(caption, msgKeyB64);
    if (encMsg == null) {
      throw Exception('Не удалось зашифровать сообщение');
    }

    final encFile = await renSdk.encryptFile(
      fileBytes,
      filename,
      mimetype,
      msgKeyB64,
    );
    if (encFile == null) {
      throw Exception('Не удалось зашифровать файл');
    }

    // Upload ciphertext bytes to backend (store server-side)
    final ciphertextBytes = base64Decode((encFile['ciphertext'] ?? '').toString());
    final uploadResp = await api.uploadMedia(
      chatId: chatId,
      ciphertextBytes: ciphertextBytes,
      filename: filename,
      mimetype: mimetype,
    );
    final uploadedId = uploadResp['file_id'];
    final fileId = (uploadedId is int)
        ? uploadedId
        : int.tryParse('$uploadedId') ?? 0;
    if (fileId <= 0) {
      throw Exception('Не удалось загрузить ciphertext файла');
    }

    final wrappedForMe = renSdk.wrapSymmetricKey(msgKeyB64, myPublicKeyB64);
    final wrappedForPeer = renSdk.wrapSymmetricKey(msgKeyB64, peerPublicKeyB64);
    if (wrappedForMe == null || wrappedForPeer == null) {
      throw Exception('Не удалось сформировать envelopes');
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
      'ciphertext': encMsg['ciphertext'],
      'nonce': encMsg['nonce'],
    });

    final metadata = [
      {
        'file_id': fileId,
        'filename': filename,
        'mimetype': mimetype,
        'size': fileBytes.length,
        'enc_file': null,
        'nonce': encFile['nonce'],
        'file_creation_date': null,
      }
    ];

    return {
      'chat_id': chatId,
      'message': messageJson,
      'message_type': 'image',
      'envelopes': envelopes,
      'metadata': metadata,
    };
  }

  Future<Map<String, dynamic>> buildEncryptedWsMediaMessage({
    required int chatId,
    required int peerId,
    required String caption,
    required List<OutgoingAttachment> attachments,
  }) async {
    if (peerId <= 0) {
      throw Exception('Некорректный peerId');
    }

    final myIdStr = await SecureStorage.readKey(Keys.UserId);
    final myId = int.tryParse(myIdStr ?? '') ?? 0;
    if (myId <= 0) {
      throw Exception('Не удалось определить userId');
    }

    final myPublicKeyB64 = (await SecureStorage.readKey(Keys.PublicKey))?.trim();
    if (myPublicKeyB64 == null || myPublicKeyB64.isEmpty) {
      throw Exception('Отсутствует публичный ключ');
    }

    final peerPublicKeyB64 = (await api.getPublicKey(peerId)).trim();

    final msgKeyB64 = renSdk.generateMessageKey().trim();

    final encMsg = renSdk.encryptMessage(caption, msgKeyB64);
    if (encMsg == null) {
      throw Exception('Не удалось зашифровать сообщение');
    }

    final wrappedForMe = renSdk.wrapSymmetricKey(msgKeyB64, myPublicKeyB64);
    final wrappedForPeer = renSdk.wrapSymmetricKey(msgKeyB64, peerPublicKeyB64);
    if (wrappedForMe == null || wrappedForPeer == null) {
      throw Exception('Не удалось сформировать envelopes');
    }

    Map<String, dynamic> env(String userId, Map<String, String> w) {
      return {
        'key': w['wrapped'],
        'ephem_pub_key': w['ephemeral_public_key'],
        'iv': w['nonce'],
      };
    }

    final envelopes = {
      '$myId': env('$myId', wrappedForMe),
      '$peerId': env('$peerId', wrappedForPeer),
    };

    final metadata = <Map<String, dynamic>>[];
    for (final att in attachments) {
      final filename = att.filename.isNotEmpty
          ? att.filename
          : 'file_${DateTime.now().millisecondsSinceEpoch}';
      final mimetype = att.mimetype.isNotEmpty ? att.mimetype : 'application/octet-stream';

      final encFile = await renSdk.encryptFile(
        Uint8List.fromList(att.bytes),
        filename,
        mimetype,
        msgKeyB64,
      );
      if (encFile == null) {
        throw Exception('Не удалось зашифровать файл');
      }

      final ciphertextBytes = base64Decode((encFile['ciphertext'] ?? '').toString());
      final uploadResp = await api.uploadMedia(
        chatId: chatId,
        ciphertextBytes: ciphertextBytes,
        filename: filename,
        mimetype: mimetype,
      );
      final uploadedId = uploadResp['file_id'];
      final fileId = (uploadedId is int) ? uploadedId : int.tryParse('$uploadedId') ?? 0;
      if (fileId <= 0) {
        throw Exception('Не удалось загрузить ciphertext файла');
      }

      metadata.add({
        'file_id': fileId,
        'filename': filename,
        'mimetype': mimetype,
        'size': att.bytes.length,
        'enc_file': null,
        'nonce': encFile['nonce'],
        'file_creation_date': null,
      });
    }

    final messageJson = jsonEncode({
      'ciphertext': encMsg['ciphertext'],
      'nonce': encMsg['nonce'],
    });

    return {
      'chat_id': chatId,
      'message': messageJson,
      'message_type': 'media',
      'envelopes': envelopes,
      'metadata': metadata,
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

    final decrypted = await _tryDecryptMessageAndKey(
      encrypted: encrypted,
      envelopes: envelopes,
      myUserId: myUserId,
      myPrivateKeyB64: myPrivateKeyB64,
    );

    return decrypted.text;
  }

  Future<({String text, List<ChatAttachment> attachments})> decryptIncomingWsMessageFull({
    required Map<String, dynamic> message,
  }) async {
    final myUserIdStr = await SecureStorage.readKey(Keys.UserId);
    final myUserId = int.tryParse(myUserIdStr ?? '') ?? 0;
    final myPrivateKeyB64 = await SecureStorage.readKey(Keys.PrivateKey);

    final encrypted = message['message'] as String? ?? '';
    final envelopes = message['envelopes'];

    final decrypted = await _tryDecryptMessageAndKey(
      encrypted: encrypted,
      envelopes: envelopes,
      myUserId: myUserId,
      myPrivateKeyB64: myPrivateKeyB64,
    );

    final attachments = await _tryDecryptAttachments(
      metadata: message['metadata'],
      msgKeyB64: decrypted.key,
    );

    return (text: decrypted.text, attachments: attachments);
  }

  String _avatarUrl(String avatarPath) {
    final p = avatarPath.trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    final normalized = p.startsWith('/') ? p.substring(1) : p;
    return '${Apiurl.api}/avatars/$normalized';
  }
}
