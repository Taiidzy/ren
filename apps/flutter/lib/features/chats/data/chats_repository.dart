import 'dart:convert';
import 'dart:io';

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

  Directory? _tempDirCache;
  Future<Directory>? _tempDirInFlight;

  Directory? _ciphertextCacheDirCache;
  Future<Directory>? _ciphertextCacheDirInFlight;

  int? _myUserIdCache;
  String? _myPrivateKeyB64Cache;
  String? _myPublicKeyB64Cache;
  final Map<int, String> _peerPublicKeyB64Cache = <int, String>{};

  final Map<int, Map<int, Uint8List>> _chatKeyBytesByChatIdAndVersion = <int, Map<int, Uint8List>>{};
  final Map<int, int> _latestChatKeyVersionByChatId = <int, int>{};

  ChatsRepository(this.api, this.renSdk);

  Future<Directory> _getTempDir() async {
    final cached = _tempDirCache;
    if (cached != null) return cached;
    final inflight = _tempDirInFlight;
    if (inflight != null) return inflight;
    final future = getTemporaryDirectory().then((d) {
      _tempDirCache = d;
      return d;
    });
    _tempDirInFlight = future;
    try {
      return await future;
    } finally {
      _tempDirInFlight = null;
    }

  }

  ({String text, String? key}) _decryptMessageWithChatKeyBytes({
    required String encrypted,
    required Uint8List keyBytes,
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

    final decrypted = renSdk.decryptMessageWithKeyBytes(ciphertext, nonce, keyBytes);
    if (decrypted == null) {
      debugPrint('decrypt: decryptMessage failed');
    }
    return (text: decrypted ?? '[encrypted]', key: base64Encode(keyBytes));
  }

  Future<Uint8List?> _getChatKeyBytesLatest(int chatId) async {
    final resp = await api.getLatestChatKey(chatId);
    final kvDyn = resp['key_version'] ?? resp['keyVersion'];
    final keyVersion = (kvDyn is int) ? kvDyn : int.tryParse('${kvDyn ?? ''}') ?? 0;
    final env = resp['envelope'];
    if (env is! Map) {
      return null;
    }

    final myPriv = await _getMyPrivateKeyB64();
    if (myPriv == null || myPriv.isEmpty) return null;

    final keyBytes = renSdk.unwrapSymmetricKeyEnvelopeBytes(env, myPriv);
    if (keyBytes == null || keyBytes.isEmpty) return null;

    final byVer = _chatKeyBytesByChatIdAndVersion.putIfAbsent(chatId, () => <int, Uint8List>{});
    byVer[keyVersion] = keyBytes;
    _latestChatKeyVersionByChatId[chatId] = keyVersion;
    return keyBytes;
  }

  Future<Uint8List?> _getChatKeyBytesForMessage({
    required int chatId,
    required int keyVersion,
  }) async {
    final byVer = _chatKeyBytesByChatIdAndVersion[chatId];
    final cached = byVer?[keyVersion];
    if (cached != null) return cached;

    // We only have "latest" API right now; fetch it and cache.
    await _getChatKeyBytesLatest(chatId);
    return _chatKeyBytesByChatIdAndVersion[chatId]?[keyVersion];
  }

  void invalidateChatKey(int chatId) {
    _latestChatKeyVersionByChatId.remove(chatId);
    _chatKeyBytesByChatIdAndVersion.remove(chatId);
  }

  Future<void> prefetchLatestChatKey(int chatId) async {
    await _getChatKeyBytesLatest(chatId);
  }

  Future<void> rotateChatKey(int chatId) async {
    if (chatId <= 0) {
      throw Exception('Некорректный chatId');
    }

    final myId = await _getMyUserId();
    if (myId <= 0) {
      throw Exception('Не удалось определить userId');
    }

    final myPublicKeyB64 = await _getMyPublicKeyB64();
    if (myPublicKeyB64 == null || myPublicKeyB64.isEmpty) {
      throw Exception('Отсутствует публичный ключ');
    }

    final participants = await api.getParticipants(chatId);

    final userIds = <int>{};
    for (final p in participants) {
      if (p is int) {
        if (p > 0) userIds.add(p);
        continue;
      }
      if (p is Map) {
        final dynId = p['user_id'] ?? p['userId'] ?? p['id'];
        final uid = (dynId is int) ? dynId : int.tryParse('${dynId ?? ''}') ?? 0;
        if (uid > 0) userIds.add(uid);
      }
    }
    userIds.add(myId);

    final publicKeysByUserId = <int, String>{
      myId: myPublicKeyB64,
    };

    final missingPublicKeys = <int>[];
    for (final uid in userIds) {
      if (uid == myId) continue;

      try {
        final pk = (await api.getPublicKey(uid)).trim();
        if (pk.isNotEmpty) {
          publicKeysByUserId[uid] = pk;
        } else {
          missingPublicKeys.add(uid);
        }
      } catch (_) {
        missingPublicKeys.add(uid);
      }
    }

    if (missingPublicKeys.isNotEmpty) {
      missingPublicKeys.sort();
      throw Exception(
        'Не удалось получить public key для пользователей: ${missingPublicKeys.join(', ')}',
      );
    }

    final newKeyB64 = renSdk.generateMessageKey().trim();
    final envelopes = renSdk.wrapSymmetricKeyEnvelopes(
      keyB64: newKeyB64,
      publicKeysByUserId: publicKeysByUserId,
    );
    if (envelopes.isEmpty) {
      throw Exception('Не удалось сформировать envelopes');
    }

    await api.rotateChatKey(chatId, envelopes);

    invalidateChatKey(chatId);
    await prefetchLatestChatKey(chatId);
  }

  Future<void> distributeChannelKey(int chatId, {required List<int> userIds}) async {
    if (chatId <= 0) {
      throw Exception('Некорректный chatId');
    }
    if (userIds.isEmpty) return;

    final myId = await _getMyUserId();
    if (myId <= 0) {
      throw Exception('Не удалось определить userId');
    }

    final myPublicKeyB64 = await _getMyPublicKeyB64();
    if (myPublicKeyB64 == null || myPublicKeyB64.isEmpty) {
      throw Exception('Отсутствует публичный ключ');
    }

    final keyBytes = await _getChatKeyBytesLatest(chatId);
    if (keyBytes == null || keyBytes.isEmpty) {
      throw Exception('Не найден ключ чата');
    }
    final keyB64 = base64Encode(keyBytes);

    final publicKeysByUserId = <int, String>{
      myId: myPublicKeyB64,
    };

    final missing = <int>[];
    for (final uid in userIds) {
      if (uid <= 0) continue;
      if (uid == myId) continue;
      try {
        final pk = (await api.getPublicKey(uid)).trim();
        if (pk.isNotEmpty) {
          publicKeysByUserId[uid] = pk;
        } else {
          missing.add(uid);
        }
      } catch (_) {
        missing.add(uid);
      }
    }
    if (missing.isNotEmpty) {
      missing.sort();
      throw Exception('Не удалось получить public key для пользователей: ${missing.join(', ')}');
    }

    final envelopes = renSdk.wrapSymmetricKeyEnvelopes(
      keyB64: keyB64,
      publicKeysByUserId: publicKeysByUserId,
    );
    if (envelopes.isEmpty) {
      throw Exception('Не удалось сформировать envelopes');
    }

    await api.distributeChatKey(chatId, envelopes);

    invalidateChatKey(chatId);
    await prefetchLatestChatKey(chatId);
  }

  Future<Directory> _getCiphertextCacheDir() async {
    final cached = _ciphertextCacheDirCache;
    if (cached != null) return cached;
    final inflight = _ciphertextCacheDirInFlight;
    if (inflight != null) return inflight;
    final future = () async {
      final dir = await _getTempDir();
      final cacheDir = Directory('${dir.path}/ren_ciphertext_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      _ciphertextCacheDirCache = cacheDir;
      return cacheDir;
    }();
    _ciphertextCacheDirInFlight = future;
    try {
      return await future;
    } finally {
      _ciphertextCacheDirInFlight = null;
    }
  }

  Future<int> _getMyUserId() async {
    final cached = _myUserIdCache;
    if (cached != null && cached > 0) return cached;
    final myUserIdStr = await SecureStorage.readKey(Keys.UserId);
    final myUserId = int.tryParse(myUserIdStr ?? '') ?? 0;
    _myUserIdCache = myUserId;
    return myUserId;
  }

  Future<String?> _getMyPrivateKeyB64() async {
    final cached = _myPrivateKeyB64Cache;
    if (cached != null && cached.trim().isNotEmpty) return cached;
    final v = await SecureStorage.readKey(Keys.PrivateKey);
    final trimmed = v?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      _myPrivateKeyB64Cache = trimmed;
    }
    return trimmed;
  }

  Future<String?> _getMyPublicKeyB64() async {
    final cached = _myPublicKeyB64Cache;
    if (cached != null && cached.trim().isNotEmpty) return cached;
    final v = await SecureStorage.readKey(Keys.PublicKey);
    final trimmed = v?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      _myPublicKeyB64Cache = trimmed;
    }
    return trimmed;
  }

  Future<String> _getPeerPublicKeyB64(int peerId) async {
    final cached = _peerPublicKeyB64Cache[peerId];
    if (cached != null && cached.isNotEmpty) return cached;
    final v = (await api.getPublicKey(peerId)).trim();
    if (v.isNotEmpty) {
      _peerPublicKeyB64Cache[peerId] = v;
    }
    return v;
  }

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
      final cacheDir = await _getCiphertextCacheDir();
      final cacheFile = File('${cacheDir.path}/$fileId.bin');

      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        _ciphertextMemoryCache[fileId] = bytes;
        return bytes;
      }

      final bytes = await api.downloadMedia(fileId);
      _ciphertextMemoryCache[fileId] = bytes;
      try {
        await cacheFile.writeAsBytes(bytes);
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
      final kind = (m['kind'] as String?) ?? 'private';
      final peerId = (m['peer_id'] is int)
          ? m['peer_id'] as int
          : int.tryParse('${m['peer_id']}');
      final peerUsername = (m['peer_username'] as String?) ?? '';
      final peerAvatar = (m['peer_avatar'] as String?) ?? '';
      final title = (m['title'] as String?) ?? '';
      final isFavorite = (m['is_favorite'] == true) || (m['isFavorite'] == true);
      final updatedAtStr = (m['updated_at'] as String?) ?? '';

      final updatedAt = DateTime.tryParse(updatedAtStr) ?? DateTime.now();

      final isGroupOrChannel = kind == 'group' || kind == 'channel';
      final name = isGroupOrChannel
          ? (title.trim().isNotEmpty ? title.trim() : (kind == 'channel' ? 'Канал' : 'Группа'))
          : (peerUsername.isNotEmpty ? peerUsername : 'User');

      final user = ChatUser(
        id: isGroupOrChannel ? id.toString() : (peerId ?? 0).toString(),
        name: name,
        avatarUrl: isGroupOrChannel ? '' : _avatarUrl(peerAvatar),
        isOnline: false,
      );

      items.add(
        ChatPreview(
          id: id.toString(),
          peerId: peerId,
          kind: kind,
          user: user,
          isFavorite: isFavorite,
          lastMessage: '',
          lastMessageAt: updatedAt,
        ),
      );
    }

    return items;
  }

  Future<List<ChatUser>> searchUsers(String query, {int limit = 15}) async {
    final raw = await api.searchUsers(query, limit: limit);
    final out = <ChatUser>[];
    for (final it in raw) {
      if (it is! Map) continue;
      final m = it.cast<String, dynamic>();
      final id = (m['id'] is int) ? m['id'] as int : int.tryParse('${m['id']}') ?? 0;
      final username = (m['username'] as String?) ?? '';
      final avatar = (m['avatar'] as String?) ?? '';
      if (id <= 0) continue;
      out.add(
        ChatUser(
          id: id.toString(),
          name: username.isNotEmpty ? username : 'User',
          avatarUrl: _avatarUrl(avatar),
          isOnline: false,
        ),
      );
    }
    return out;
  }

  Future<List<ChatPreview>> searchGroupsAndChannels(String query, {int limit = 15}) async {
    final raw = await api.searchChats(query, limit: limit);
    final out = <ChatPreview>[];

    for (final it in raw) {
      if (it is! Map) continue;
      final m = it.cast<String, dynamic>();
      final id = (m['id'] is int) ? m['id'] as int : int.tryParse('${m['id']}') ?? 0;
      final kind = (m['kind'] as String?) ?? '';
      if (id <= 0) continue;
      if (kind != 'group' && kind != 'channel') continue;

      final title = (m['title'] as String?) ?? '';
      final resolvedTitle = title.trim().isNotEmpty
          ? title.trim()
          : (kind == 'channel' ? 'Канал' : 'Группа');

      out.add(
        ChatPreview(
          id: id.toString(),
          peerId: null,
          kind: kind,
          user: ChatUser(
            id: id.toString(),
            name: resolvedTitle,
            avatarUrl: '',
            isOnline: false,
          ),
          isFavorite: false,
          lastMessage: '',
          lastMessageAt: DateTime.now(),
        ),
      );
    }

    return out;
  }

  Future<List<ChatUser>> favorites() async {
    final chats = await fetchChats();
    final out = <ChatUser>[];
    final favChats = chats.where((c) => c.isFavorite).take(5);
    for (final c in favChats) {
      out.add(c.user);
    }
    return out;
  }

  Future<void> setFavorite(int chatId, {required bool favorite}) async {
    if (favorite) {
      await api.addFavorite(chatId);
    } else {
      await api.removeFavorite(chatId);
    }
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

    final myUserId = await _getMyUserId();
    final privateKey = await _getMyPrivateKeyB64();

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
      final createdAt = (DateTime.tryParse(createdAtStr) ?? DateTime.now()).toLocal();

      final kvDyn = m['key_version'] ?? m['keyVersion'];
      final keyVersion = (kvDyn is int) ? kvDyn : int.tryParse('${kvDyn ?? ''}');

      final encrypted = (m['message'] as String?) ?? '';

      final decrypted = await _tryDecryptMessageAndKey(
        encrypted: encrypted,
        envelopes: m['envelopes'],
        myUserId: myUserId,
        myPrivateKeyB64: privateKey,
        chatId: chatId,
        keyVersion: keyVersion,
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
          senderId: senderId.toString(),
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

    Uint8List keyBytes;
    try {
      keyBytes = base64Decode(key);
    } catch (_) {
      return const [];
    }

    final dir = await _getTempDir();
    final outByIndex = List<ChatAttachment?>.filled(metadata.length, null);

    Future<void> processAt(int index) async {
      final item = metadata[index];
      if (item is! Map) return;
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
        return;
      }

      Uint8List? ciphertextBytes;
      String? ciphertextB64;

      int? fileId;
      if (fileIdDyn is int) {
        fileId = fileIdDyn;
      } else if (fileIdDyn is String) {
        fileId = int.tryParse(fileIdDyn);
      }
      if (fileId != null && fileId > 0) {
        try {
          ciphertextBytes = await _getCiphertextBytes(fileId);
        } catch (e) {
          debugPrint('download media failed fileId=$fileId err=$e');
          return;
        }
      } else if (encFile != null && encFile.isNotEmpty) {
        ciphertextB64 = encFile;
      }

      final bytes = (ciphertextBytes != null)
          ? await renSdk.decryptFileBytesRawWithKeyBytes(ciphertextBytes, nonce, keyBytes)
          : (ciphertextB64 != null && ciphertextB64.isNotEmpty)
              ? await renSdk.decryptFileBytes(ciphertextB64, nonce, key)
              : null;
      if (bytes == null) return;

      final safeName = filename.isNotEmpty
          ? filename
          : 'file_${DateTime.now().millisecondsSinceEpoch}';
      final path = '${dir.path}/$safeName';
      final f = File(path);
      await f.writeAsBytes(bytes);

      outByIndex[index] = ChatAttachment(
        localPath: path,
        filename: filename,
        mimetype: mimetype,
        size: size,
      );
    }

    const maxConcurrent = 3;
    final inFlight = <Future<void>>[];

    for (var i = 0; i < metadata.length; i++) {
      inFlight.add(processAt(i));
      if (inFlight.length >= maxConcurrent) {
        await Future.wait(inFlight);
        inFlight.clear();
      }
    }
    if (inFlight.isNotEmpty) {
      await Future.wait(inFlight);
    }

    final out = <ChatAttachment>[];
    for (final a in outByIndex) {
      if (a != null) out.add(a);
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

    final msgKeyBytes = renSdk.unwrapSymmetricKeyBytes(wrapped, eph, wrapNonce, priv);
    if (msgKeyBytes == null || msgKeyBytes.isEmpty) {
      return (text: '[encrypted]', key: null);
    }

    final msgKey = base64Encode(msgKeyBytes);
    final decrypted = renSdk.decryptMessageWithKeyBytes(ciphertext, nonce, msgKeyBytes);
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
    int? chatId,
    int? keyVersion,
  }) async {
    // 1) If per-message envelopes exist (private chat / legacy), use them
    if (envelopes is Map) {
      return _decryptMessageWithKey(
        encrypted: encrypted,
        envelopes: envelopes,
        myUserId: myUserId,
        myPrivateKeyB64: myPrivateKeyB64,
      );
    }

    // 2) Otherwise, try decrypt using group/channel chat key
    final cid = chatId ?? 0;
    final kv = keyVersion ?? 0;
    if (cid <= 0) {
      return (text: '[encrypted]', key: null);
    }
    final keyBytes = await _getChatKeyBytesForMessage(chatId: cid, keyVersion: kv);
    if (keyBytes == null || keyBytes.isEmpty) {
      return (text: '[encrypted]', key: null);
    }
    return _decryptMessageWithChatKeyBytes(encrypted: encrypted, keyBytes: keyBytes);
  }

  Future<Map<String, dynamic>> buildEncryptedWsGroupMessage({
    required int chatId,
    required String plaintext,
  }) async {
    Uint8List? keyBytes = await _getChatKeyBytesLatest(chatId);
    if (keyBytes == null || keyBytes.isEmpty) {
      try {
        await rotateChatKey(chatId);
      } catch (_) {
        // ignore: rethrow original error below
      }
      keyBytes = await _getChatKeyBytesLatest(chatId);
      if (keyBytes == null || keyBytes.isEmpty) {
        throw Exception('Не найден ключ чата');
      }
    }

    final keyB64 = base64Encode(keyBytes);
    final enc = renSdk.encryptMessage(plaintext, keyB64);
    if (enc == null) {
      throw Exception('Не удалось зашифровать сообщение');
    }

    final keyVersion = _latestChatKeyVersionByChatId[chatId] ?? 0;

    final messageJson = jsonEncode({
      'ciphertext': enc['ciphertext'],
      'nonce': enc['nonce'],
    });

    return {
      'chat_id': chatId,
      'message': messageJson,
      'message_type': 'text',
      'envelopes': null,
      'metadata': null,
      'key_version': keyVersion,
    };
  }

  Future<Map<String, dynamic>> buildEncryptedWsGroupMediaMessage({
    required int chatId,
    required String caption,
    required List<OutgoingAttachment> attachments,
  }) async {
    if (attachments.isEmpty) {
      return buildEncryptedWsGroupMessage(chatId: chatId, plaintext: caption);
    }

    Uint8List? keyBytes = await _getChatKeyBytesLatest(chatId);
    if (keyBytes == null || keyBytes.isEmpty) {
      try {
        await rotateChatKey(chatId);
      } catch (_) {
        // ignore
      }
      keyBytes = await _getChatKeyBytesLatest(chatId);
      if (keyBytes == null || keyBytes.isEmpty) {
        throw Exception('Не найден ключ чата');
      }
    }

    final msgKeyB64 = base64Encode(keyBytes);
    final keyVersion = _latestChatKeyVersionByChatId[chatId] ?? 0;

    final encMsg = renSdk.encryptMessage(caption, msgKeyB64);
    if (encMsg == null) {
      throw Exception('Не удалось зашифровать сообщение');
    }

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
      'envelopes': null,
      'metadata': metadata,
      'key_version': keyVersion,
    };
  }

  Future<ChatPreview> createPrivateChat(int peerId) async {
    final myUserId = await _getMyUserId();

    final json = await api.createChat(
      kind: 'private',
      userIds: [myUserId, peerId],
    );

    final id = (json['id'] is int) ? json['id'] as int : int.tryParse('${json['id']}') ?? 0;

    final isFavorite = (json['is_favorite'] == true) || (json['isFavorite'] == true);

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
      isFavorite: isFavorite,
      lastMessage: '',
      lastMessageAt: DateTime.now(),
    );
  }

  Future<ChatPreview> createGroupChat({
    required String title,
    required List<int> userIds,
  }) async {
    final myUserId = await _getMyUserId();
    final uniq = <int>{...userIds}..add(myUserId);

    final json = await api.createChat(
      kind: 'group',
      title: title.trim().isEmpty ? null : title.trim(),
      userIds: uniq.where((e) => e > 0).toList(),
    );

    final id = (json['id'] is int) ? json['id'] as int : int.tryParse('${json['id']}') ?? 0;
    if (id > 0) {
      await rotateChatKey(id);
    }
    final isFavorite = (json['is_favorite'] == true) || (json['isFavorite'] == true);
    final resolvedTitle = ((json['title'] as String?) ?? title).trim();

    return ChatPreview(
      id: id.toString(),
      peerId: null,
      kind: (json['kind'] as String?) ?? 'group',
      user: ChatUser(
        id: id.toString(),
        name: resolvedTitle.isNotEmpty ? resolvedTitle : 'Группа',
        avatarUrl: '',
        isOnline: false,
      ),
      isFavorite: isFavorite,
      lastMessage: '',
      lastMessageAt: DateTime.now(),
    );
  }

  Future<ChatPreview> createChannel({
    required String title,
    required List<int> userIds,
  }) async {
    final myUserId = await _getMyUserId();
    final uniq = <int>{...userIds}..add(myUserId);

    final json = await api.createChat(
      kind: 'channel',
      title: title.trim().isEmpty ? null : title.trim(),
      userIds: uniq.where((e) => e > 0).toList(),
    );

    final id = (json['id'] is int) ? json['id'] as int : int.tryParse('${json['id']}') ?? 0;
    if (id > 0) {
      await rotateChatKey(id);
    }
    final isFavorite = (json['is_favorite'] == true) || (json['isFavorite'] == true);
    final resolvedTitle = ((json['title'] as String?) ?? title).trim();

    return ChatPreview(
      id: id.toString(),
      peerId: null,
      kind: (json['kind'] as String?) ?? 'channel',
      user: ChatUser(
        id: id.toString(),
        name: resolvedTitle.isNotEmpty ? resolvedTitle : 'Канал',
        avatarUrl: '',
        isOnline: false,
      ),
      isFavorite: isFavorite,
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
    final myUserId = await _getMyUserId();
    final myPrivateKeyB64 = await _getMyPrivateKeyB64();
    final myPublicKeyB64 = await _getMyPublicKeyB64();

    if (myUserId == 0) {
      throw Exception('Не найден userId');
    }
    if (myPrivateKeyB64 == null || myPrivateKeyB64.isEmpty) {
      throw Exception('Не найден приватный ключ');
    }
    if (myPublicKeyB64 == null || myPublicKeyB64.isEmpty) {
      throw Exception('Не найден публичный ключ');
    }

    final peerPublicKeyB64 = await _getPeerPublicKeyB64(peerId);

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

    final envMe = renSdk.envelopeFromWrappedKeyMap(wrappedForMe);
    final envPeer = renSdk.envelopeFromWrappedKeyMap(wrappedForPeer);
    if (envMe == null || envPeer == null) {
      throw Exception('Не удалось сформировать envelopes');
    }

    final envelopes = <String, dynamic>{
      '$myUserId': envMe,
      '$peerId': envPeer,
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
    final myUserId = await _getMyUserId();
    final myPrivateKeyB64 = await _getMyPrivateKeyB64();
    final myPublicKeyB64 = await _getMyPublicKeyB64();

    if (myUserId == 0) {
      throw Exception('Не найден userId');
    }
    if (myPrivateKeyB64 == null || myPrivateKeyB64.isEmpty) {
      throw Exception('Не найден приватный ключ');
    }
    if (myPublicKeyB64 == null || myPublicKeyB64.isEmpty) {
      throw Exception('Не найден публичный ключ');
    }

    final peerPublicKeyB64 = await _getPeerPublicKeyB64(peerId);

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

    final myId = await _getMyUserId();
    if (myId <= 0) {
      throw Exception('Не удалось определить userId');
    }

    final myPublicKeyB64 = await _getMyPublicKeyB64();
    if (myPublicKeyB64 == null || myPublicKeyB64.isEmpty) {
      throw Exception('Отсутствует публичный ключ');
    }

    final peerPublicKeyB64 = await _getPeerPublicKeyB64(peerId);

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

    final envMe = renSdk.envelopeFromWrappedKeyMap(wrappedForMe);
    final envPeer = renSdk.envelopeFromWrappedKeyMap(wrappedForPeer);
    if (envMe == null || envPeer == null) {
      throw Exception('Не удалось сформировать envelopes');
    }

    final envelopes = {
      '$myId': envMe,
      '$peerId': envPeer,
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
    final myUserId = await _getMyUserId();
    final myPrivateKeyB64 = await _getMyPrivateKeyB64();

    final cidDyn = message['chat_id'] ?? message['chatId'];
    final chatId = (cidDyn is int) ? cidDyn : int.tryParse('${cidDyn ?? ''}');
    final kvDyn = message['key_version'] ?? message['keyVersion'];
    final keyVersion = (kvDyn is int) ? kvDyn : int.tryParse('${kvDyn ?? ''}');

    final encrypted = message['message'] as String? ?? '';
    final envelopes = message['envelopes'];

    final decrypted = await _tryDecryptMessageAndKey(
      encrypted: encrypted,
      envelopes: envelopes,
      myUserId: myUserId,
      myPrivateKeyB64: myPrivateKeyB64,
      chatId: chatId,
      keyVersion: keyVersion,
    );

    return decrypted.text;
  }

  Future<({String text, List<ChatAttachment> attachments})> decryptIncomingWsMessageFull({
    required Map<String, dynamic> message,
  }) async {
    final myUserId = await _getMyUserId();
    final myPrivateKeyB64 = await _getMyPrivateKeyB64();

    final cidDyn = message['chat_id'] ?? message['chatId'];
    final chatId = (cidDyn is int) ? cidDyn : int.tryParse('${cidDyn ?? ''}');
    final kvDyn = message['key_version'] ?? message['keyVersion'];
    final keyVersion = (kvDyn is int) ? kvDyn : int.tryParse('${kvDyn ?? ''}');

    final encrypted = message['message'] as String? ?? '';
    final envelopes = message['envelopes'];

    final decrypted = await _tryDecryptMessageAndKey(
      encrypted: encrypted,
      envelopes: envelopes,
      myUserId: myUserId,
      myPrivateKeyB64: myPrivateKeyB64,
      chatId: chatId,
      keyVersion: keyVersion,
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
