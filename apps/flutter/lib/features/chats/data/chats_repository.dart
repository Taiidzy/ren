import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/cache/chats_local_cache.dart';
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

Future<Map<String, String>?> _encryptAttachmentInIsolate({
  required Uint8List bytes,
  required String filename,
  required String mimetype,
  required String keyB64,
}) {
  return Isolate.run(() {
    return RenSdk.instance.encryptFileSync(bytes, filename, mimetype, keyB64);
  });
}

class ChatsRepository {
  final ChatsApi api;
  final RenSdk renSdk;
  final ChatsLocalCache _localCache = ChatsLocalCache();

  final ValueNotifier<bool> chatsSyncing = ValueNotifier<bool>(false);
  final Map<int, ValueNotifier<bool>> _messagesSyncingByChat =
      <int, ValueNotifier<bool>>{};

  final Map<int, Uint8List> _ciphertextMemoryCache = <int, Uint8List>{};
  final Map<int, Future<Uint8List>> _ciphertextInFlight =
      <int, Future<Uint8List>>{};

  Directory? _tempDirCache;
  Future<Directory>? _tempDirInFlight;

  Directory? _ciphertextCacheDirCache;
  Future<Directory>? _ciphertextCacheDirInFlight;

  final Map<int, String> _peerPublicKeyB64Cache = <int, String>{};
  Future<void> _mediaPipelineTail = Future<void>.value();

  static const int _maxUploadRetries = 2;

  ChatsRepository(this.api, this.renSdk);

  bool _isPrivateKind(String kind) => kind.trim().toLowerCase() == 'private';

  Future<T> _runInMediaPipeline<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _mediaPipelineTail = _mediaPipelineTail.catchError((_) {}).then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>> _uploadMediaWithRetry({
    required int chatId,
    required Uint8List ciphertextBytes,
    required String filename,
    required String mimetype,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= _maxUploadRetries; attempt++) {
      try {
        return await api.uploadMedia(
          chatId: chatId,
          ciphertextBytes: ciphertextBytes,
          filename: filename,
          mimetype: mimetype,
        );
      } catch (e) {
        lastError = e;
        if (attempt >= _maxUploadRetries) break;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw Exception('upload media failed: $lastError');
  }

  ValueNotifier<bool> messagesSyncingNotifier(int chatId) {
    return _messagesSyncingByChat.putIfAbsent(
      chatId,
      () => ValueNotifier<bool>(false),
    );
  }

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
    final myUserIdStr = await SecureStorage.readKey(Keys.userId);
    return int.tryParse(myUserIdStr ?? '') ?? 0;
  }

  Future<String?> _getMyPrivateKeyB64() async {
    final v = await SecureStorage.readKey(Keys.privateKey);
    return v?.trim();
  }

  Future<String?> _getMyPublicKeyB64() async {
    final v = await SecureStorage.readKey(Keys.publicKey);
    return v?.trim();
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

  Future<List<ChatPreview>> _fetchChatsRemote() async {
    final raw = await api.listChats();
    final items = <ChatPreview>[];

    for (final it in raw) {
      final m = (it as Map).cast<String, dynamic>();
      final id = (m['id'] is int)
          ? m['id'] as int
          : int.tryParse('${m['id']}') ?? 0;
      final peerId = (m['peer_id'] is int)
          ? m['peer_id'] as int
          : int.tryParse('${m['peer_id']}');
      final peerUsername = (m['peer_username'] as String?) ?? '';
      final peerAvatar = (m['peer_avatar'] as String?) ?? '';
      final title = ((m['title'] as String?) ?? '').trim();
      final kind = ((m['kind'] as String?) ?? 'private').trim().toLowerCase();
      final isFavorite =
          (m['is_favorite'] == true) || (m['isFavorite'] == true);
      final unreadCount = (m['unread_count'] is int)
          ? m['unread_count'] as int
          : int.tryParse('${m['unread_count'] ?? ''}') ?? 0;
      final myRoleRaw = ((m['my_role'] as String?) ?? 'member').trim();
      final myRole = myRoleRaw.isEmpty ? 'member' : myRoleRaw.toLowerCase();
      final updatedAtStr = (m['updated_at'] as String?) ?? '';
      final lastMessageId = (m['last_message_id'] is int)
          ? m['last_message_id'] as int
          : int.tryParse('${m['last_message_id'] ?? ''}') ?? 0;
      final lastMessageRaw = (m['last_message'] as String?) ?? '';
      final lastMessageType = ((m['last_message_type'] as String?) ?? '')
          .trim()
          .toLowerCase();
      final lastMessageOutgoing = m['last_message_is_outgoing'] == true;
      final lastMessageDelivered = m['last_message_is_delivered'] == true;
      final lastMessageRead = m['last_message_is_read'] == true;
      final lastMessageAtStr = (m['last_message_created_at'] as String?) ?? '';

      final updatedAt = DateTime.tryParse(updatedAtStr) ?? DateTime.now();
      final lastMessageAt = DateTime.tryParse(lastMessageAtStr) ?? updatedAt;

      final userName = _isPrivateKind(kind)
          ? (peerUsername.isNotEmpty ? peerUsername : 'User')
          : (title.isNotEmpty ? title : 'Chat');
      final user = ChatUser(
        id: (peerId ?? 0).toString(),
        name: userName,
        avatarUrl: _avatarUrl(peerAvatar),
        isOnline: false,
      );

      items.add(
        ChatPreview(
          id: id.toString(),
          peerId: peerId,
          kind: kind,
          user: user,
          isFavorite: isFavorite,
          lastMessage: _buildChatListMessagePreview(
            kind: kind,
            messageId: lastMessageId,
            rawMessage: lastMessageRaw,
            messageType: lastMessageType,
          ),
          lastMessageAt: lastMessageAt,
          unreadCount: unreadCount < 0 ? 0 : unreadCount,
          myRole: myRole,
          lastMessageIsMine: lastMessageOutgoing,
          lastMessageIsPending: false,
          lastMessageIsDelivered: lastMessageDelivered,
          lastMessageIsRead: lastMessageRead,
        ),
      );
    }

    final withPending = await _applyLocalPendingLastMessage(items);
    withPending.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return withPending;
  }

  String _buildChatListMessagePreview({
    required String kind,
    required int messageId,
    required String rawMessage,
    required String messageType,
  }) {
    if (messageId <= 0) return '';
    if (messageType == 'voice_message') return 'Голосовое сообщение';
    if (messageType == 'video_message') return 'Видео';
    if (messageType == 'image' || messageType == 'photo') return 'Фото';
    if (messageType == 'file') return 'Файл';

    final trimmed = rawMessage.trim();
    if (trimmed.isEmpty) return 'Сообщение';

    // В private чатах сообщение обычно E2EE: не показываем ciphertext в списке.
    if (_isPrivateKind(kind)) return 'Сообщение';
    return trimmed;
  }

  String _localPendingPreview(ChatMessage message) {
    final text = message.text.trim();
    if (text.isNotEmpty) return text;
    if (message.attachments.isNotEmpty) {
      final first = message.attachments.first;
      if (first.isImage) return 'Фото';
      if (first.isVideo) return 'Видео';
      if (first.mimetype.startsWith('audio/')) return 'Голосовое сообщение';
      return 'Файл';
    }
    return 'Сообщение';
  }

  Future<List<ChatPreview>> _applyLocalPendingLastMessage(
    List<ChatPreview> source,
  ) async {
    if (source.isEmpty) return source;
    final out = List<ChatPreview>.from(source);
    for (var i = 0; i < out.length; i++) {
      final chat = out[i];
      final chatId = int.tryParse(chat.id) ?? 0;
      if (chatId <= 0) continue;
      final local = await _localCache.readMessages(chatId);
      if (local.isEmpty) continue;
      final latest = local.last;
      if (!latest.isMe || !latest.id.startsWith('local_')) continue;
      out[i] = ChatPreview(
        id: chat.id,
        peerId: chat.peerId,
        kind: chat.kind,
        user: chat.user,
        isFavorite: chat.isFavorite,
        lastMessage: _localPendingPreview(latest),
        lastMessageAt: latest.sentAt,
        unreadCount: chat.unreadCount,
        myRole: chat.myRole,
        lastMessageIsMine: true,
        lastMessageIsPending: true,
        lastMessageIsDelivered: false,
        lastMessageIsRead: false,
      );
    }
    return out;
  }

  Future<List<ChatPreview>> getCachedChats() async {
    return _localCache.readChats();
  }

  Future<List<ChatPreview>> fetchChats() async {
    final items = await _fetchChatsRemote();
    await _localCache.writeChats(items);
    return items;
  }

  Future<List<ChatPreview>> syncChats() async {
    if (chatsSyncing.value) {
      return getCachedChats();
    }
    chatsSyncing.value = true;
    try {
      final fresh = await _fetchChatsRemote();
      await _localCache.writeChats(fresh);
      return fresh;
    } finally {
      chatsSyncing.value = false;
    }
  }

  Future<List<ChatUser>> searchUsers(String query, {int limit = 15}) async {
    final raw = await api.searchUsers(query, limit: limit);
    final out = <ChatUser>[];
    for (final it in raw) {
      if (it is! Map) continue;
      final m = it.cast<String, dynamic>();
      final id = (m['id'] is int)
          ? m['id'] as int
          : int.tryParse('${m['id']}') ?? 0;
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

  Future<List<ChatMessage>> _fetchMessagesRemote(
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
      final messageId = (m['id'] is int)
          ? m['id'] as int
          : int.tryParse('${m['id']}') ?? 0;
      final senderId = (m['sender_id'] is int)
          ? m['sender_id'] as int
          : int.tryParse('${m['sender_id']}') ?? 0;
      final isDelivered = m['is_delivered'] == true || m['isDelivered'] == true;
      final isRead = m['is_read'] == true || m['isRead'] == true;

      final replyDyn = m['reply_to_message_id'] ?? m['replyToMessageId'];
      final replyId = (replyDyn is int)
          ? replyDyn
          : int.tryParse('${replyDyn ?? ''}');

      final createdAtStr = (m['created_at'] as String?) ?? '';
      final createdAt = (DateTime.tryParse(createdAtStr) ?? DateTime.now())
          .toLocal();

      final encrypted = (m['message'] as String?) ?? '';
      final messageType = ((m['message_type'] as String?) ?? 'text')
          .trim()
          .toLowerCase();

      final decrypted = (messageType == 'system')
          ? (text: encrypted, key: null)
          : await _tryDecryptMessageAndKey(
              encrypted: encrypted,
              envelopes: m['envelopes'],
              myUserId: myUserId,
              myPrivateKeyB64: privateKey,
            );

      final msgKey = decrypted.key;
      final attachments = await _tryDecryptAttachments(
        chatId: chatId,
        messageId: messageId,
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
          replyToMessageId: (replyId != null && replyId > 0)
              ? replyId.toString()
              : null,
          isDelivered: isDelivered,
          isRead: isRead,
        ),
      );
    }

    return out;
  }

  Future<List<ChatMessage>> getCachedMessages(int chatId) async {
    return _localCache.readMessages(chatId);
  }

  Future<void> _writeMessagesCache(
    int chatId,
    List<ChatMessage> remote, {
    int? beforeId,
    int? afterId,
  }) async {
    if (beforeId == null && afterId == null) {
      await _localCache.writeMessages(chatId, remote);
      return;
    }

    final cached = await _localCache.readMessages(chatId);
    final byId = <String, ChatMessage>{};
    for (final m in cached) {
      byId[m.id] = m;
    }
    for (final m in remote) {
      byId[m.id] = m;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    await _localCache.writeMessages(chatId, merged);
  }

  Future<List<ChatMessage>> fetchMessages(
    int chatId, {
    int? limit,
    int? beforeId,
    int? afterId,
  }) async {
    final remote = await _fetchMessagesRemote(
      chatId,
      limit: limit,
      beforeId: beforeId,
      afterId: afterId,
    );
    await _writeMessagesCache(
      chatId,
      remote,
      beforeId: beforeId,
      afterId: afterId,
    );
    return remote;
  }

  Future<List<ChatMessage>> syncMessages(
    int chatId, {
    int? limit,
    int? beforeId,
    int? afterId,
  }) async {
    final notifier = messagesSyncingNotifier(chatId);
    if (!notifier.value) {
      notifier.value = true;
    }
    try {
      final remote = await _fetchMessagesRemote(
        chatId,
        limit: limit,
        beforeId: beforeId,
        afterId: afterId,
      );
      await _writeMessagesCache(
        chatId,
        remote,
        beforeId: beforeId,
        afterId: afterId,
      );
      return remote;
    } finally {
      notifier.value = false;
    }
  }

  Future<List<ChatAttachment>> _tryDecryptAttachments({
    required int chatId,
    required int messageId,
    required dynamic metadata,
    required String? msgKeyB64,
  }) async {
    if (metadata is! List) return const [];
    final key = msgKeyB64?.trim();
    final hasKey = key != null && key.isNotEmpty;

    Uint8List? keyBytes;
    if (hasKey) {
      try {
        keyBytes = base64Decode(key);
      } catch (_) {
        return const [];
      }
    }

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

      Uint8List? bytes;
      if (hasKey) {
        if (nonce == null || nonce.isEmpty || keyBytes == null) {
          return;
        }
        bytes = (ciphertextBytes != null)
            ? await renSdk.decryptFileBytesRawWithKeyBytes(
                ciphertextBytes,
                nonce,
                keyBytes,
              )
            : (ciphertextB64 != null && ciphertextB64.isNotEmpty)
            ? await renSdk.decryptFileBytes(ciphertextB64, nonce, key)
            : null;
      } else {
        // non-E2EE attachments: store bytes as-is
        if (ciphertextBytes != null) {
          bytes = ciphertextBytes;
        } else if (ciphertextB64 != null && ciphertextB64.isNotEmpty) {
          try {
            bytes = Uint8List.fromList(base64Decode(ciphertextB64));
          } catch (_) {
            bytes = null;
          }
        }
      }
      if (bytes == null) return;

      final path = await _localCache.saveMediaBytes(
        chatId: chatId,
        messageId: messageId,
        fileId: fileId,
        filename: filename,
        bytes: bytes,
      );

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
      // non-E2EE chats may carry plaintext directly in message
      return (text: encrypted, key: null);
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

    String? asString(dynamic v) =>
        (v is String && v.trim().isNotEmpty) ? v.trim() : null;

    final wrapped = asString(env['key']) ?? asString(env['wrapped']);
    final eph =
        asString(env['ephem_pub_key']) ?? asString(env['ephemeral_public_key']);
    final wrapNonce = asString(env['iv']) ?? asString(env['nonce']);

    if (wrapped == null || eph == null || wrapNonce == null) {
      debugPrint(
        'decrypt: missing wrapped/eph/nonce in envelope for user=$myUserId',
      );
      return (text: '[encrypted]', key: null);
    }

    final msgKeyBytes = renSdk.unwrapSymmetricKeyBytes(
      wrapped,
      eph,
      wrapNonce,
      priv,
    );
    if (msgKeyBytes == null || msgKeyBytes.isEmpty) {
      return (text: '[encrypted]', key: null);
    }

    final msgKey = base64Encode(msgKeyBytes);
    final decrypted = renSdk.decryptMessageWithKeyBytes(
      ciphertext,
      nonce,
      msgKeyBytes,
    );
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

  Future<ChatPreview> createPrivateChat(
    int peerId, {
    String? fallbackPeerName,
    String? fallbackPeerAvatarUrl,
  }) async {
    final myUserId = await _getMyUserId();

    final json = await api.createChat(
      kind: 'private',
      userIds: [myUserId, peerId],
    );

    final id = (json['id'] is int)
        ? json['id'] as int
        : int.tryParse('${json['id']}') ?? 0;

    final isFavorite =
        (json['is_favorite'] == true) || (json['isFavorite'] == true);

    final peerUsername = ((json['peer_username'] as String?) ?? '').trim();
    final fallbackName = (fallbackPeerName ?? '').trim();
    final resolvedName = peerUsername.isNotEmpty
        ? peerUsername
        : (fallbackName.isNotEmpty ? fallbackName : 'User');

    final peerAvatar = ((json['peer_avatar'] as String?) ?? '').trim();
    final fallbackAvatar = (fallbackPeerAvatarUrl ?? '').trim();
    final resolvedAvatar = peerAvatar.isNotEmpty
        ? _avatarUrl(peerAvatar)
        : fallbackAvatar;

    return ChatPreview(
      id: id.toString(),
      peerId: peerId,
      kind: (json['kind'] as String?) ?? 'private',
      user: ChatUser(
        id: peerId.toString(),
        name: resolvedName,
        avatarUrl: resolvedAvatar,
        isOnline: false,
      ),
      isFavorite: isFavorite,
      lastMessage: '',
      lastMessageAt: DateTime.now(),
      unreadCount: 0,
      myRole: ((json['my_role'] as String?) ?? 'member').trim().isEmpty
          ? 'member'
          : ((json['my_role'] as String?) ?? 'member').trim().toLowerCase(),
      lastMessageIsMine: false,
      lastMessageIsPending: false,
      lastMessageIsDelivered: false,
      lastMessageIsRead: false,
    );
  }

  ChatPreview _chatPreviewFromCreateResponse(
    Map<String, dynamic> json, {
    required String kind,
    int? peerId,
    String? fallbackName,
  }) {
    final id = (json['id'] is int)
        ? json['id'] as int
        : int.tryParse('${json['id']}') ?? 0;
    final isFavorite =
        (json['is_favorite'] == true) || (json['isFavorite'] == true);
    final title = ((json['title'] as String?) ?? '').trim();

    final name = _isPrivateKind(kind)
        ? ((fallbackName ?? 'User').trim().isEmpty
              ? 'User'
              : (fallbackName ?? 'User').trim())
        : (title.isNotEmpty ? title : (fallbackName ?? 'Chat'));

    return ChatPreview(
      id: id.toString(),
      peerId: peerId,
      kind: kind,
      user: ChatUser(
        id: (peerId ?? 0).toString(),
        name: name,
        avatarUrl: '',
        isOnline: false,
      ),
      isFavorite: isFavorite,
      lastMessage: '',
      lastMessageAt: DateTime.now(),
      unreadCount: 0,
      myRole: ((json['my_role'] as String?) ?? 'member').trim().isEmpty
          ? 'member'
          : ((json['my_role'] as String?) ?? 'member').trim().toLowerCase(),
      lastMessageIsMine: false,
      lastMessageIsPending: false,
      lastMessageIsDelivered: false,
      lastMessageIsRead: false,
    );
  }

  Future<ChatPreview> createGroupChat({
    required String title,
    required List<int> memberUserIds,
  }) async {
    final myUserId = await _getMyUserId();
    final users = <int>{
      myUserId,
      ...memberUserIds.where((e) => e > 0),
    }.toList(growable: false);
    final json = await api.createChat(
      kind: 'group',
      title: title,
      userIds: users,
    );
    return _chatPreviewFromCreateResponse(
      json,
      kind: 'group',
      fallbackName: title.trim().isEmpty ? 'Group' : title.trim(),
    );
  }

  Future<ChatPreview> createChannel({
    required String title,
    required List<int> memberUserIds,
  }) async {
    final myUserId = await _getMyUserId();
    final users = <int>{
      myUserId,
      ...memberUserIds.where((e) => e > 0),
    }.toList(growable: false);
    final json = await api.createChat(
      kind: 'channel',
      title: title,
      userIds: users,
    );
    return _chatPreviewFromCreateResponse(
      json,
      kind: 'channel',
      fallbackName: title.trim().isEmpty ? 'Channel' : title.trim(),
    );
  }

  Future<List<ChatMember>> listMembers(int chatId) async {
    final raw = await api.listMembers(chatId);
    final out = <ChatMember>[];
    for (final it in raw) {
      if (it is! Map) continue;
      final m = it.cast<String, dynamic>();
      final userId = (m['user_id'] is int)
          ? m['user_id'] as int
          : int.tryParse('${m['user_id'] ?? ''}') ?? 0;
      if (userId <= 0) continue;
      final username = ((m['username'] as String?) ?? '').trim();
      final avatarRaw = ((m['avatar'] as String?) ?? '').trim();
      final role = ((m['role'] as String?) ?? 'member').trim();
      final joinedAt =
          DateTime.tryParse('${m['joined_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      out.add(
        ChatMember(
          userId: userId,
          username: username.isEmpty ? 'User' : username,
          avatarUrl: _avatarUrl(avatarRaw),
          role: role.isEmpty ? 'member' : role,
          joinedAt: joinedAt,
        ),
      );
    }
    return out;
  }

  Future<void> addMember(
    int chatId, {
    required int userId,
    String? role,
  }) async {
    await api.addMember(chatId, userId: userId, role: role);
  }

  Future<void> updateMemberRole(
    int chatId, {
    required int userId,
    required String role,
  }) async {
    await api.updateMemberRole(chatId, userId: userId, role: role);
  }

  Future<void> removeMember(int chatId, {required int userId}) async {
    await api.removeMember(chatId, userId: userId);
  }

  Future<void> updateChatInfo(
    int chatId, {
    String? title,
    String? avatarPath,
  }) async {
    await api.updateChatInfo(chatId, title: title, avatarPath: avatarPath);
  }

  Future<void> deleteChat(int chatId, {bool forAll = false}) async {
    await api.deleteChat(chatId, forAll: forAll);
  }

  Future<int> markChatRead(int chatId, {int? messageId}) async {
    final json = await api.markChatRead(chatId, messageId: messageId);
    final lastRead = (json['last_read_message_id'] is int)
        ? json['last_read_message_id'] as int
        : int.tryParse('${json['last_read_message_id'] ?? ''}') ?? 0;
    return lastRead;
  }

  Future<int> markChatDelivered(int chatId, {int? messageId}) async {
    final json = await api.markChatDelivered(chatId, messageId: messageId);
    final lastDelivered = (json['last_delivered_message_id'] is int)
        ? json['last_delivered_message_id'] as int
        : int.tryParse('${json['last_delivered_message_id'] ?? ''}') ?? 0;
    return lastDelivered;
  }

  Future<Map<String, dynamic>> buildOutgoingWsTextMessage({
    required int chatId,
    required String chatKind,
    int? peerId,
    required String plaintext,
  }) async {
    if (!_isPrivateKind(chatKind)) {
      return {
        'chat_id': chatId,
        'message': plaintext,
        'message_type': 'text',
        'envelopes': null,
        'metadata': null,
      };
    }

    final peer = peerId ?? 0;
    if (peer <= 0) {
      throw Exception('Некорректный peerId для private-чата');
    }

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

    final peerPublicKeyB64 = await _getPeerPublicKeyB64(peer);

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
      throw Exception(
        'Ошибка E2EE: не удалось развернуть собственный envelope (ключи не совпадают)',
      );
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
      '$peer': env('$peer', wrappedForPeer),
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
    return _runInMediaPipeline(() async {
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

      final encFile = await _encryptAttachmentInIsolate(
        bytes: fileBytes,
        filename: filename,
        mimetype: mimetype,
        keyB64: msgKeyB64,
      );
      if (encFile == null) {
        throw Exception('Не удалось зашифровать файл');
      }

      // Upload ciphertext bytes to backend (store server-side)
      final ciphertextBytes = base64Decode(
        (encFile['ciphertext'] ?? '').toString(),
      );
      final uploadResp = await _uploadMediaWithRetry(
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
      final wrappedForPeer = renSdk.wrapSymmetricKey(
        msgKeyB64,
        peerPublicKeyB64,
      );
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
        },
      ];

      return {
        'chat_id': chatId,
        'message': messageJson,
        'message_type': 'image',
        'envelopes': envelopes,
        'metadata': metadata,
      };
    });
  }

  Future<Map<String, dynamic>> buildOutgoingWsMediaMessage({
    required int chatId,
    required String chatKind,
    int? peerId,
    required String caption,
    required List<OutgoingAttachment> attachments,
  }) async {
    return _runInMediaPipeline(() async {
      if (!_isPrivateKind(chatKind)) {
        final metadata = <Map<String, dynamic>>[];
        for (final att in attachments) {
          final filename = att.filename.isNotEmpty
              ? att.filename
              : 'file_${DateTime.now().millisecondsSinceEpoch}';
          final mimetype = att.mimetype.isNotEmpty
              ? att.mimetype
              : 'application/octet-stream';
          final rawBytes = att.bytes is Uint8List
              ? att.bytes as Uint8List
              : Uint8List.fromList(att.bytes);

          final uploadResp = await _uploadMediaWithRetry(
            chatId: chatId,
            ciphertextBytes: rawBytes,
            filename: filename,
            mimetype: mimetype,
          );
          final uploadedId = uploadResp['file_id'];
          final fileId = (uploadedId is int)
              ? uploadedId
              : int.tryParse('$uploadedId') ?? 0;
          if (fileId <= 0) {
            throw Exception('Не удалось загрузить файл');
          }

          metadata.add({
            'file_id': fileId,
            'filename': filename,
            'mimetype': mimetype,
            'size': rawBytes.length,
            'enc_file': null,
            'nonce': null,
            'file_creation_date': null,
          });
        }

        return {
          'chat_id': chatId,
          'message': caption,
          'message_type': 'media',
          'envelopes': null,
          'metadata': metadata,
        };
      }

      final peer = peerId ?? 0;
      if (peer <= 0) {
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

      final peerPublicKeyB64 = await _getPeerPublicKeyB64(peer);

      final msgKeyB64 = renSdk.generateMessageKey().trim();

      final encMsg = renSdk.encryptMessage(caption, msgKeyB64);
      if (encMsg == null) {
        throw Exception('Не удалось зашифровать сообщение');
      }

      final wrappedForMe = renSdk.wrapSymmetricKey(msgKeyB64, myPublicKeyB64);
      final wrappedForPeer = renSdk.wrapSymmetricKey(
        msgKeyB64,
        peerPublicKeyB64,
      );
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
        '$peer': env('$peer', wrappedForPeer),
      };

      final metadata = <Map<String, dynamic>>[];
      for (final att in attachments) {
        final filename = att.filename.isNotEmpty
            ? att.filename
            : 'file_${DateTime.now().millisecondsSinceEpoch}';
        final mimetype = att.mimetype.isNotEmpty
            ? att.mimetype
            : 'application/octet-stream';

        final rawBytes = att.bytes is Uint8List
            ? att.bytes as Uint8List
            : Uint8List.fromList(att.bytes);

        final encFile = await _encryptAttachmentInIsolate(
          bytes: rawBytes,
          filename: filename,
          mimetype: mimetype,
          keyB64: msgKeyB64,
        );
        if (encFile == null) {
          throw Exception('Не удалось зашифровать файл');
        }

        final ciphertextBytes = base64Decode(
          (encFile['ciphertext'] ?? '').toString(),
        );
        final uploadResp = await _uploadMediaWithRetry(
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

        metadata.add({
          'file_id': fileId,
          'filename': filename,
          'mimetype': mimetype,
          'size': rawBytes.length,
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
    });
  }

  Future<String> decryptIncomingWsMessage({
    required Map<String, dynamic> message,
  }) async {
    final myUserId = await _getMyUserId();
    final myPrivateKeyB64 = await _getMyPrivateKeyB64();

    final encrypted = message['message'] as String? ?? '';
    final messageType = ((message['message_type'] as String?) ?? 'text')
        .trim()
        .toLowerCase();
    if (messageType == 'system') {
      return encrypted;
    }
    final envelopes = message['envelopes'];

    final decrypted = await _tryDecryptMessageAndKey(
      encrypted: encrypted,
      envelopes: envelopes,
      myUserId: myUserId,
      myPrivateKeyB64: myPrivateKeyB64,
    );

    return decrypted.text;
  }

  Future<({String text, List<ChatAttachment> attachments})>
  decryptIncomingWsMessageFull({required Map<String, dynamic> message}) async {
    final myUserId = await _getMyUserId();
    final myPrivateKeyB64 = await _getMyPrivateKeyB64();

    final encrypted = message['message'] as String? ?? '';
    final messageType = ((message['message_type'] as String?) ?? 'text')
        .trim()
        .toLowerCase();
    if (messageType == 'system') {
      return (text: encrypted, attachments: const <ChatAttachment>[]);
    }
    final envelopes = message['envelopes'];

    final decrypted = await _tryDecryptMessageAndKey(
      encrypted: encrypted,
      envelopes: envelopes,
      myUserId: myUserId,
      myPrivateKeyB64: myPrivateKeyB64,
    );

    final chatId = (message['chat_id'] is int)
        ? message['chat_id'] as int
        : int.tryParse('${message['chat_id'] ?? ''}') ?? 0;
    final messageId = (message['id'] is int)
        ? message['id'] as int
        : int.tryParse('${message['id'] ?? ''}') ?? 0;

    final attachments = await _tryDecryptAttachments(
      chatId: chatId,
      messageId: messageId,
      metadata: message['metadata'],
      msgKeyB64: decrypted.key,
    );

    return (text: decrypted.text, attachments: attachments);
  }

  Future<int> getCacheLimitBytes() async {
    return _localCache.readCacheLimitBytes();
  }

  Future<void> setCacheLimitBytes(int bytes) async {
    await _localCache.writeCacheLimitBytes(bytes);
  }

  Future<int> getCacheSizeBytes() async {
    return _localCache.cacheSizeBytes();
  }

  Future<CacheUsageStats> getCacheUsageStats() async {
    return _localCache.usageStats();
  }

  Future<void> saveChatsSnapshot(List<ChatPreview> chats) async {
    await _localCache.writeChats(chats);
  }

  Future<void> saveMessagesSnapshot(
    int chatId,
    List<ChatMessage> messages,
  ) async {
    await _localCache.writeMessages(chatId, messages);
  }

  Future<double?> loadChatScrollOffset(String chatId) async {
    return _localCache.readChatScrollOffset(chatId);
  }

  Future<void> saveChatScrollOffset(String chatId, double offset) async {
    await _localCache.writeChatScrollOffset(chatId, offset);
  }

  Future<void> clearAppCache({
    bool includeMedia = true,
    bool includeChats = true,
    bool includeMessages = true,
  }) async {
    await _localCache.clearCache(
      includeMedia: includeMedia,
      includeChats: includeChats,
      includeMessages: includeMessages,
    );
    if (includeChats) {
      chatsSyncing.value = false;
    }
    if (includeMessages) {
      for (final notifier in _messagesSyncingByChat.values) {
        notifier.value = false;
      }
    }
    if (includeMedia) {
      _ciphertextMemoryCache.clear();
      _ciphertextInFlight.clear();
      final dir = _ciphertextCacheDirCache;
      if (dir != null) {
        try {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        } catch (_) {}
      }
      _ciphertextCacheDirCache = null;
      _ciphertextCacheDirInFlight = null;
    }
  }

  String _avatarUrl(String avatarPath) {
    final p = avatarPath.trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    final normalized = p.startsWith('/') ? p.substring(1) : p;
    return '${Apiurl.api}/avatars/$normalized';
  }

  void resetSessionState() {
    _peerPublicKeyB64Cache.clear();
    _chatIndexClearNotifiers();
  }

  void _chatIndexClearNotifiers() {
    chatsSyncing.value = false;
    for (final notifier in _messagesSyncingByChat.values) {
      notifier.value = false;
    }
  }
}
