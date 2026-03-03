import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:ren/features/chats/domain/chat_models.dart';

class ChatsLocalCache {
  static const int defaultCacheLimitBytes = 256 * 1024 * 1024;
  static const int minCacheLimitBytes = 64 * 1024 * 1024;
  static const int maxCacheLimitBytes = 50 * 1024 * 1024 * 1024;

  Directory? _rootDirCache;
  Future<Directory>? _rootDirInFlight;

  Future<Directory> _rootDir() async {
    final cached = _rootDirCache;
    if (cached != null) return cached;
    final inflight = _rootDirInFlight;
    if (inflight != null) return inflight;

    final future = () async {
      final support = await getApplicationSupportDirectory();
      final root = Directory('${support.path}/ren_cache');
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      _rootDirCache = root;
      return root;
    }();

    _rootDirInFlight = future;
    try {
      return await future;
    } finally {
      _rootDirInFlight = null;
    }
  }

  Future<File> _chatsFile() async {
    final root = await _rootDir();
    return File('${root.path}/chats.json');
  }

  Future<File> _messagesFile(int chatId) async {
    final root = await _rootDir();
    return File('${root.path}/messages_$chatId.json');
  }

  Future<File> _settingsFile() async {
    final root = await _rootDir();
    return File('${root.path}/settings.json');
  }

  Future<File> _pendingMediaUploadsFile() async {
    final root = await _rootDir();
    return File('${root.path}/pending_media_uploads.json');
  }

  Future<File> _decryptedTextsFile() async {
    final root = await _rootDir();
    return File('${root.path}/decrypted_texts.json');
  }

  Future<Directory> _mediaDir() async {
    final root = await _rootDir();
    final d = Directory('${root.path}/media');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  Future<void> _atomicWriteJson(File file, Map<String, dynamic> json) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  Future<Map<String, dynamic>?> _readJsonIfExists(File file) async {
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _chatToJson(ChatPreview c) {
    return {
      'id': c.id,
      'peerId': c.peerId,
      'kind': c.kind,
      'isFavorite': c.isFavorite,
      'lastMessage': c.lastMessage,
      'lastMessageAt': c.lastMessageAt.toIso8601String(),
      'unreadCount': c.unreadCount,
      'myRole': c.myRole,
      'lastMessageIsMine': c.lastMessageIsMine,
      'lastMessageIsPending': c.lastMessageIsPending,
      'lastMessageIsDelivered': c.lastMessageIsDelivered,
      'lastMessageIsRead': c.lastMessageIsRead,
      'user': {
        'id': c.user.id,
        'name': c.user.name,
        'avatarUrl': c.user.avatarUrl,
        'isOnline': c.user.isOnline,
      },
    };
  }

  ChatPreview? _chatFromJson(dynamic input) {
    if (input is! Map) return null;
    final m = input.cast<String, dynamic>();
    final u = m['user'];
    if (u is! Map) return null;
    final um = u.cast<String, dynamic>();

    return ChatPreview(
      id: '${m['id'] ?? ''}',
      peerId: (m['peerId'] is int)
          ? m['peerId'] as int
          : int.tryParse('${m['peerId'] ?? ''}'),
      kind: (m['kind'] as String?) ?? 'private',
      user: ChatUser(
        id: '${um['id'] ?? ''}',
        name: (um['name'] as String?) ?? 'User',
        nickname: (um['nickname'] as String?),
        avatarUrl: (um['avatarUrl'] as String?) ?? '',
        isOnline: um['isOnline'] == true,
      ),
      isFavorite: m['isFavorite'] == true,
      lastMessage: (m['lastMessage'] as String?) ?? '',
      lastMessageAt:
          DateTime.tryParse('${m['lastMessageAt'] ?? ''}') ?? DateTime.now(),
      unreadCount: (m['unreadCount'] is int)
          ? m['unreadCount'] as int
          : int.tryParse('${m['unreadCount'] ?? ''}') ?? 0,
      myRole: ((m['myRole'] as String?) ?? 'member').trim().isEmpty
          ? 'member'
          : ((m['myRole'] as String?) ?? 'member').trim().toLowerCase(),
      lastMessageIsMine: m['lastMessageIsMine'] == true,
      lastMessageIsPending: m['lastMessageIsPending'] == true,
      lastMessageIsDelivered: m['lastMessageIsDelivered'] == true,
      lastMessageIsRead: m['lastMessageIsRead'] == true,
    );
  }

  Map<String, dynamic> _messageToJson(ChatMessage m) {
    return {
      'id': m.id,
      'chatId': m.chatId,
      'isMe': m.isMe,
      'text': m.text,
      'sentAt': m.sentAt.toIso8601String(),
      'replyToMessageId': m.replyToMessageId,
      'isDelivered': m.isDelivered,
      'isRead': m.isRead,
      'attachments': m.attachments
          .map(
            (a) => {
              'localPath': a.localPath,
              'filename': a.filename,
              'mimetype': a.mimetype,
              'size': a.size,
              'transferState': a.transferState.name,
              'transferProgress': a.transferProgress,
            },
          )
          .toList(),
    };
  }

  ChatMessage? _messageFromJson(dynamic input) {
    if (input is! Map) return null;
    final m = input.cast<String, dynamic>();
    final attachments = <ChatAttachment>[];
    final rawAttachments = m['attachments'];
    if (rawAttachments is List) {
      for (final it in rawAttachments) {
        if (it is! Map) continue;
        final am = it.cast<String, dynamic>();
        attachments.add(
          ChatAttachment(
            localPath: (am['localPath'] as String?) ?? '',
            filename: (am['filename'] as String?) ?? 'file',
            mimetype: (am['mimetype'] as String?) ?? 'application/octet-stream',
            size: (am['size'] is int)
                ? am['size'] as int
                : int.tryParse('${am['size'] ?? ''}') ?? 0,
            transferState: _parseTransferState(am['transferState'] as String?),
            transferProgress: (am['transferProgress'] is num)
                ? (am['transferProgress'] as num).toDouble()
                : double.tryParse('${am['transferProgress'] ?? ''}') ?? 1.0,
          ),
        );
      }
    }

    return ChatMessage(
      id: '${m['id'] ?? ''}',
      chatId: '${m['chatId'] ?? ''}',
      isMe: m['isMe'] == true,
      text: (m['text'] as String?) ?? '',
      attachments: attachments,
      sentAt: DateTime.tryParse('${m['sentAt'] ?? ''}') ?? DateTime.now(),
      replyToMessageId: (m['replyToMessageId'] as String?),
      isDelivered: m['isDelivered'] == true,
      isRead: m['isRead'] == true,
    );
  }

  Future<List<ChatPreview>> readChats() async {
    final file = await _chatsFile();
    final decoded = await _readJsonIfExists(file);
    final list = decoded?['items'];
    if (list is! List) return const [];
    final out = <ChatPreview>[];
    for (final it in list) {
      final chat = _chatFromJson(it);
      if (chat != null) out.add(chat);
    }
    out.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return out;
  }

  Future<void> writeChats(List<ChatPreview> chats) async {
    final file = await _chatsFile();
    await _atomicWriteJson(file, {
      'updatedAt': DateTime.now().toIso8601String(),
      'items': chats.map(_chatToJson).toList(),
    });
  }

  Future<List<ChatMessage>> readMessages(int chatId) async {
    final file = await _messagesFile(chatId);
    final decoded = await _readJsonIfExists(file);
    final list = decoded?['items'];
    if (list is! List) return const [];
    final out = <ChatMessage>[];
    for (final it in list) {
      final msg = _messageFromJson(it);
      if (msg != null) out.add(msg);
    }
    out.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return out;
  }

  Future<void> writeMessages(int chatId, List<ChatMessage> messages) async {
    final file = await _messagesFile(chatId);
    await _atomicWriteJson(file, {
      'updatedAt': DateTime.now().toIso8601String(),
      'items': messages.map(_messageToJson).toList(),
    });
  }

  Future<Map<String, String>> readDecryptedTextsForChat(int chatId) async {
    final entries = await readDecryptedTextEntriesForChat(chatId);
    final out = <String, String>{};
    for (final e in entries.entries) {
      if (e.value.text.trim().isNotEmpty) {
        out[e.key] = e.value.text;
      }
    }
    return out;
  }

  Future<Map<String, DecryptedTextCacheEntry>> readDecryptedTextEntriesForChat(
    int chatId,
  ) async {
    final file = await _decryptedTextsFile();
    final decoded = await _readJsonIfExists(file);
    final all = decoded?['items'];
    if (all is! Map) return const <String, DecryptedTextCacheEntry>{};
    final byChat = all['$chatId'];
    if (byChat is! Map) return const <String, DecryptedTextCacheEntry>{};
    final out = <String, DecryptedTextCacheEntry>{};
    byChat.forEach((key, value) {
      final k = key.toString().trim();
      if (k.isEmpty) return;
      if (value is String) {
        final text = value.trim();
        if (text.isEmpty) return;
        out[k] = DecryptedTextCacheEntry(text: text);
        return;
      }
      if (value is Map) {
        final map = value.cast<String, dynamic>();
        final text = (map['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) return;
        final hash = (map['ciphertext_hash'] as String?)?.trim();
        out[k] = DecryptedTextCacheEntry(
          text: text,
          ciphertextHash: (hash == null || hash.isEmpty) ? null : hash,
        );
      }
    });
    return out;
  }

  Future<void> writeDecryptedText({
    required int chatId,
    required int messageId,
    required String text,
    String? ciphertextHash,
  }) async {
    if (chatId <= 0 || messageId <= 0) return;
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    final file = await _decryptedTextsFile();
    final decoded = await _readJsonIfExists(file) ?? <String, dynamic>{};
    final rawItems = decoded['items'];
    final items = (rawItems is Map<String, dynamic>)
        ? Map<String, dynamic>.from(rawItems)
        : <String, dynamic>{};
    final rawChat = items['$chatId'];
    final byChat = (rawChat is Map<String, dynamic>)
        ? Map<String, dynamic>.from(rawChat)
        : <String, dynamic>{};

    final normalizedHash = ciphertextHash?.trim();
    byChat['$messageId'] = <String, dynamic>{
      'text': normalized,
      if (normalizedHash != null && normalizedHash.isNotEmpty)
        'ciphertext_hash': normalizedHash,
    };
    items['$chatId'] = byChat;
    decoded['items'] = items;
    decoded['updatedAt'] = DateTime.now().toIso8601String();
    await _atomicWriteJson(file, decoded);
  }

  Future<int> readCacheLimitBytes() async {
    final file = await _settingsFile();
    final decoded = await _readJsonIfExists(file);
    final limit = decoded?['cacheLimitBytes'];
    if (limit is int && limit > 0) return limit;
    if (limit is String) {
      final parsed = int.tryParse(limit);
      if (parsed != null && parsed > 0) return parsed;
    }
    return defaultCacheLimitBytes;
  }

  Future<void> writeCacheLimitBytes(int bytes) async {
    final normalized = bytes.clamp(minCacheLimitBytes, maxCacheLimitBytes);
    final file = await _settingsFile();
    final decoded = await _readJsonIfExists(file) ?? <String, dynamic>{};
    decoded['cacheLimitBytes'] = normalized;
    decoded['updatedAt'] = DateTime.now().toIso8601String();
    await _atomicWriteJson(file, decoded);
  }

  Future<double?> readChatScrollOffset(String chatId) async {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) return null;
    final file = await _settingsFile();
    final decoded = await _readJsonIfExists(file);
    final offsets = decoded?['chatScrollOffsets'];
    if (offsets is! Map) return null;
    final value = offsets[normalizedChatId];
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }

  Future<void> writeChatScrollOffset(String chatId, double offset) async {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty || !offset.isFinite) return;
    final clamped = offset < 0 ? 0.0 : offset;

    final file = await _settingsFile();
    final decoded = await _readJsonIfExists(file) ?? <String, dynamic>{};
    final rawOffsets = decoded['chatScrollOffsets'];
    final offsets = (rawOffsets is Map<String, dynamic>)
        ? Map<String, dynamic>.from(rawOffsets)
        : <String, dynamic>{};

    offsets[normalizedChatId] = clamped;
    decoded['chatScrollOffsets'] = offsets;
    decoded['updatedAt'] = DateTime.now().toIso8601String();
    await _atomicWriteJson(file, decoded);
  }

  Future<String> saveMediaBytes({
    required int chatId,
    required int messageId,
    required int? fileId,
    required String filename,
    required Uint8List bytes,
  }) async {
    final mediaRoot = await _mediaDir();
    final safeName = filename.trim().isNotEmpty
        ? filename.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        : 'file_${DateTime.now().millisecondsSinceEpoch}';
    final key = fileId != null && fileId > 0 ? 'f$fileId' : 'm$messageId';
    final chatDir = Directory('${mediaRoot.path}/chat_$chatId');
    if (!await chatDir.exists()) {
      await chatDir.create(recursive: true);
    }

    final file = File('${chatDir.path}/${key}_$safeName');
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    await _enforceCacheLimit();
    return file.path;
  }

  Future<int> cacheSizeBytes() async {
    final root = await _rootDir();
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } catch (_) {}
    }
    return total;
  }

  Future<CacheUsageStats> usageStats() async {
    final root = await _rootDir();
    var chats = 0;
    var messages = 0;
    var media = 0;

    final chatsFile = await _chatsFile();
    if (await chatsFile.exists()) {
      try {
        chats = await chatsFile.length();
      } catch (_) {}
    }

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.last
          : '';
      if (name.startsWith('messages_') && name.endsWith('.json')) {
        try {
          messages += await entity.length();
        } catch (_) {}
      }
    }

    final mediaRoot = await _mediaDir();
    if (await mediaRoot.exists()) {
      await for (final entity in mediaRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        try {
          media += await entity.length();
        } catch (_) {}
      }
    }

    return CacheUsageStats(
      chatsBytes: chats,
      messagesBytes: messages,
      mediaBytes: media,
    );
  }

  Future<void> _enforceCacheLimit() async {
    final limit = await readCacheLimitBytes();
    final mediaRoot = await _mediaDir();
    if (!await mediaRoot.exists()) return;

    final files = <File>[];
    var total = 0;
    await for (final entity in mediaRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      files.add(entity);
      try {
        total += await entity.length();
      } catch (_) {}
    }

    if (total <= limit) return;

    files.sort((a, b) {
      final am = a.statSync().modified;
      final bm = b.statSync().modified;
      return am.compareTo(bm);
    });

    for (final file in files) {
      if (total <= limit) break;
      try {
        final size = await file.length();
        await file.delete();
        total -= size;
      } catch (_) {}
    }
  }

  Future<void> clearCache({
    bool includeMedia = true,
    bool includeChats = true,
    bool includeMessages = true,
    bool includeDecryptedHistory = false,
  }) async {
    final root = await _rootDir();
    if (!await root.exists()) return;

    if (includeChats) {
      final chats = await _chatsFile();
      if (await chats.exists()) {
        await chats.delete();
      }
    }

    if (includeMessages) {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        if (name.startsWith('messages_') && name.endsWith('.json')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
      if (includeDecryptedHistory) {
        final decrypted = await _decryptedTextsFile();
        if (await decrypted.exists()) {
          try {
            await decrypted.delete();
          } catch (_) {}
        }
      }
      final pending = await _pendingMediaUploadsFile();
      if (await pending.exists()) {
        try {
          await pending.delete();
        } catch (_) {}
      }
    }

    if (includeMedia) {
      final media = await _mediaDir();
      if (await media.exists()) {
        await media.delete(recursive: true);
      }
    }
  }

  Future<List<PendingMediaUploadTaskEntry>> readPendingMediaUploadTasksForChat(
    int chatId,
  ) async {
    final file = await _pendingMediaUploadsFile();
    final decoded = await _readJsonIfExists(file);
    final list = decoded?['items'];
    if (list is! List) return const <PendingMediaUploadTaskEntry>[];
    final out = <PendingMediaUploadTaskEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final entry = PendingMediaUploadTaskEntry.fromJson(m);
      if (entry == null || entry.chatId != chatId) continue;
      out.add(entry);
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  Future<void> upsertPendingMediaUploadTask(
    PendingMediaUploadTaskEntry task,
  ) async {
    final file = await _pendingMediaUploadsFile();
    final decoded = await _readJsonIfExists(file) ?? <String, dynamic>{};
    final raw = decoded['items'];
    final list = (raw is List) ? List<dynamic>.from(raw) : <dynamic>[];
    final idx = list.indexWhere((e) {
      if (e is! Map) return false;
      return '${e['taskId'] ?? ''}' == task.taskId;
    });
    final taskJson = task.toJson();
    if (idx >= 0) {
      list[idx] = taskJson;
    } else {
      list.add(taskJson);
    }
    decoded['items'] = list;
    decoded['updatedAt'] = DateTime.now().toIso8601String();
    await _atomicWriteJson(file, decoded);
  }

  Future<void> removePendingMediaUploadTask(String taskId) async {
    if (taskId.trim().isEmpty) return;
    final file = await _pendingMediaUploadsFile();
    final decoded = await _readJsonIfExists(file) ?? <String, dynamic>{};
    final raw = decoded['items'];
    final list = (raw is List) ? List<dynamic>.from(raw) : <dynamic>[];
    list.removeWhere((e) {
      if (e is! Map) return false;
      return '${e['taskId'] ?? ''}' == taskId;
    });
    decoded['items'] = list;
    decoded['updatedAt'] = DateTime.now().toIso8601String();
    await _atomicWriteJson(file, decoded);
  }
}

AttachmentTransferState _parseTransferState(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'uploading':
      return AttachmentTransferState.uploading;
    case 'downloading':
      return AttachmentTransferState.downloading;
    case 'decrypting':
      return AttachmentTransferState.decrypting;
    case 'failed':
      return AttachmentTransferState.failed;
    default:
      return AttachmentTransferState.ready;
  }
}

class CacheUsageStats {
  final int chatsBytes;
  final int messagesBytes;
  final int mediaBytes;

  const CacheUsageStats({
    required this.chatsBytes,
    required this.messagesBytes,
    required this.mediaBytes,
  });

  int get totalBytes => chatsBytes + messagesBytes + mediaBytes;
}

class DecryptedTextCacheEntry {
  final String text;
  final String? ciphertextHash;

  const DecryptedTextCacheEntry({required this.text, this.ciphertextHash});
}

class PendingMediaUploadTaskEntry {
  final String taskId;
  final String clientMessageId;
  final int chatId;
  final String chatKind;
  final int? peerId;
  final String wsType;
  final String caption;
  final int? replyToMessageId;
  final DateTime createdAt;
  final List<PendingMediaUploadAttachmentEntry> attachments;

  const PendingMediaUploadTaskEntry({
    required this.taskId,
    required this.clientMessageId,
    required this.chatId,
    required this.chatKind,
    required this.peerId,
    required this.wsType,
    required this.caption,
    required this.replyToMessageId,
    required this.createdAt,
    required this.attachments,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'taskId': taskId,
    'clientMessageId': clientMessageId,
    'chatId': chatId,
    'chatKind': chatKind,
    'peerId': peerId,
    'wsType': wsType,
    'caption': caption,
    'replyToMessageId': replyToMessageId,
    'createdAt': createdAt.toIso8601String(),
    'attachments': attachments.map((a) => a.toJson()).toList(),
  };

  static PendingMediaUploadTaskEntry? fromJson(Map<String, dynamic> m) {
    final taskId = ('${m['taskId'] ?? ''}').trim();
    final clientMessageId = ('${m['clientMessageId'] ?? ''}').trim();
    final chatId = (m['chatId'] is int)
        ? m['chatId'] as int
        : int.tryParse('${m['chatId'] ?? ''}') ?? 0;
    if (taskId.isEmpty || clientMessageId.isEmpty || chatId <= 0) return null;
    final rawAttachments = m['attachments'];
    if (rawAttachments is! List || rawAttachments.isEmpty) return null;
    final attachments = <PendingMediaUploadAttachmentEntry>[];
    for (final item in rawAttachments) {
      if (item is! Map) continue;
      final a = PendingMediaUploadAttachmentEntry.fromJson(
        item.cast<String, dynamic>(),
      );
      if (a == null) continue;
      attachments.add(a);
    }
    if (attachments.isEmpty) return null;
    final createdAt =
        DateTime.tryParse('${m['createdAt'] ?? ''}') ?? DateTime.now();
    return PendingMediaUploadTaskEntry(
      taskId: taskId,
      clientMessageId: clientMessageId,
      chatId: chatId,
      chatKind: (m['chatKind'] as String?)?.trim().toLowerCase() ?? 'private',
      peerId: (m['peerId'] is int)
          ? m['peerId'] as int
          : int.tryParse('${m['peerId'] ?? ''}'),
      wsType: (m['wsType'] as String?)?.trim().toLowerCase() ?? 'send_message',
      caption: (m['caption'] as String?) ?? '',
      replyToMessageId: (m['replyToMessageId'] is int)
          ? m['replyToMessageId'] as int
          : int.tryParse('${m['replyToMessageId'] ?? ''}'),
      createdAt: createdAt,
      attachments: attachments,
    );
  }
}

class PendingMediaUploadAttachmentEntry {
  final String localPath;
  final String filename;
  final String mimetype;
  final int sizeBytes;

  const PendingMediaUploadAttachmentEntry({
    required this.localPath,
    required this.filename,
    required this.mimetype,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'localPath': localPath,
    'filename': filename,
    'mimetype': mimetype,
    'sizeBytes': sizeBytes,
  };

  static PendingMediaUploadAttachmentEntry? fromJson(Map<String, dynamic> m) {
    final localPath = (m['localPath'] as String?)?.trim() ?? '';
    if (localPath.isEmpty) return null;
    return PendingMediaUploadAttachmentEntry(
      localPath: localPath,
      filename: (m['filename'] as String?) ?? 'file',
      mimetype: (m['mimetype'] as String?) ?? 'application/octet-stream',
      sizeBytes: (m['sizeBytes'] is int)
          ? m['sizeBytes'] as int
          : int.tryParse('${m['sizeBytes'] ?? ''}') ?? 0,
    );
  }
}
