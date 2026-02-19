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
        avatarUrl: (um['avatarUrl'] as String?) ?? '',
        isOnline: um['isOnline'] == true,
      ),
      isFavorite: m['isFavorite'] == true,
      lastMessage: (m['lastMessage'] as String?) ?? '',
      lastMessageAt:
          DateTime.tryParse('${m['lastMessageAt'] ?? ''}') ?? DateTime.now(),
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
      'attachments': m.attachments
          .map(
            (a) => {
              'localPath': a.localPath,
              'filename': a.filename,
              'mimetype': a.mimetype,
              'size': a.size,
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
    await _atomicWriteJson(file, {
      'cacheLimitBytes': normalized,
      'updatedAt': DateTime.now().toIso8601String(),
    });
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
    }

    if (includeMedia) {
      final media = await _mediaDir();
      if (await media.exists()) {
        await media.delete(recursive: true);
      }
    }
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
