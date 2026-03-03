import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ren/core/cache/chats_local_cache.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/e2ee/attachment_cipher.dart';
import 'package:ren/core/e2ee/signal_protocol_client.dart';
import 'package:ren/features/chats/data/chats_api.dart';
import 'package:ren/features/chats/data/chats_repository.dart';

class _FakeSignalProtocolClient implements SignalProtocolClient {
  @override
  Stream<IdentityChangeEvent> get identityChanges => const Stream.empty();

  @override
  Future<String> decrypt({
    required int peerUserId,
    required String ciphertext,
    int deviceId = 1,
  }) async {
    final decoded = utf8.decode(base64Decode(ciphertext));
    final parts = decoded.split('::');
    if (parts.length < 3 || parts.first != 'enc') {
      throw StateError('bad ciphertext');
    }
    return parts.sublist(2).join('::');
  }

  @override
  Future<String> encrypt({
    required int peerUserId,
    required String plaintext,
    int deviceId = 1,
    Map<String, dynamic>? preKeyBundle,
  }) async {
    final raw = 'enc::$peerUserId::$plaintext';
    return base64Encode(utf8.encode(raw));
  }

  @override
  Future<String> exportBackup({
    required int userId,
    int deviceId = 1,
    required String backupSecretBase64,
  }) async => '';

  @override
  Future<String> getFingerprint({
    required int peerUserId,
    int deviceId = 1,
  }) async => '';

  @override
  Future<bool> hasSession({required int peerUserId, int deviceId = 1}) async =>
      true;

  @override
  Future<Map<String, dynamic>> initUser({
    required int userId,
    int deviceId = 1,
  }) async => <String, dynamic>{};

  @override
  Future<bool> importBackup({
    required int userId,
    int deviceId = 1,
    required String backupSecretBase64,
    required String encryptedPayload,
  }) async => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> resetSession({
    required int peerUserId,
    int deviceId = 1,
  }) async {}
}

class _FakeChatsApi extends ChatsApi {
  _FakeChatsApi() : super(Dio());

  final List<Uint8List> uploaded = <Uint8List>[];
  final Map<String, List<int>> _chunked = <String, List<int>>{};
  int _uploadCounter = 0;

  @override
  Future<Map<String, dynamic>> uploadMedia({
    required int chatId,
    required List<int> ciphertextBytes,
    required String filename,
    required String mimetype,
  }) async {
    uploaded.add(Uint8List.fromList(ciphertextBytes));
    return <String, dynamic>{
      'file_id': 1000 + uploaded.length,
      'filename': filename,
      'mimetype': mimetype,
      'size': ciphertextBytes.length,
    };
  }

  @override
  Future<Map<String, dynamic>> initChunkedMediaUpload({
    required int chatId,
    required String filename,
    required String mimetype,
    required int totalSize,
    required int totalChunks,
    required int chunkSize,
  }) async {
    _uploadCounter += 1;
    final id = 'u$_uploadCounter';
    _chunked[id] = <int>[];
    return <String, dynamic>{'upload_id': id, 'next_chunk_index': 0};
  }

  @override
  Future<Map<String, dynamic>> uploadMediaChunk({
    required String uploadId,
    required int chunkIndex,
    required int totalChunks,
    required List<int> chunkBytes,
  }) async {
    final acc = _chunked.putIfAbsent(uploadId, () => <int>[]);
    acc.addAll(chunkBytes);
    return <String, dynamic>{
      'upload_id': uploadId,
      'next_chunk_index': chunkIndex + 1,
      'total_chunks': totalChunks,
      'received_size': acc.length,
      'total_size': acc.length,
    };
  }

  @override
  Future<Map<String, dynamic>> finalizeChunkedMediaUpload({
    required String uploadId,
  }) async {
    final bytes = Uint8List.fromList(_chunked[uploadId] ?? <int>[]);
    uploaded.add(bytes);
    return <String, dynamic>{
      'file_id': 1000 + uploaded.length,
      'filename': 'chunked.bin',
      'mimetype': 'application/octet-stream',
      'size': bytes.length,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      Keys.userId: '7',
      Keys.token: 'test-token',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          switch (call.method) {
            case 'getApplicationDocumentsDirectory':
            case 'getApplicationSupportDirectory':
            case 'getTemporaryDirectory':
              return Directory.systemTemp.path;
          }
          return Directory.systemTemp.path;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  test('AttachmentCipher encrypt/decrypt round-trip', () async {
    final plain = Uint8List.fromList(List<int>.generate(128, (i) => i % 256));
    final encrypted = await AttachmentCipher.encrypt(plain);
    final restored = await AttachmentCipher.decrypt(
      ciphertext: encrypted.ciphertext,
      key: encrypted.key,
      nonce: encrypted.nonce,
    );

    expect(restored, plain);
    expect(
      AttachmentCipher.sha256Base64(restored),
      encrypted.plaintextSha256Base64,
    );
  });

  test(
    'decryptIncomingWsMessage supports signal_ciphertext_by_user alias',
    () async {
      final repo = ChatsRepository(
        _FakeChatsApi(),
        _FakeSignalProtocolClient(),
      );
      final decrypted = await repo.decryptIncomingWsMessage(
        message: <String, dynamic>{
          'sender_id': 9,
          'message_type': 'text',
          'message': jsonEncode(<String, dynamic>{
            'signal_ciphertext_by_user': <String, dynamic>{
              '7': base64Encode(utf8.encode('enc::9::hello')),
            },
          }),
        },
      );

      expect(decrypted, 'hello');
    },
  );

  test(
    'buildOutgoingWsMediaMessage encrypts upload and sends encrypted descriptor',
    () async {
      final api = _FakeChatsApi();
      final signal = _FakeSignalProtocolClient();
      final repo = ChatsRepository(api, signal);
      final raw = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9]);

      final payload = await repo.buildOutgoingWsMediaMessage(
        chatId: 42,
        chatKind: 'private',
        peerId: 9,
        caption: 'caption',
        attachments: <OutgoingAttachment>[
          OutgoingAttachment(
            bytes: raw,
            filename: 'voice.ogg',
            mimetype: 'audio/ogg',
          ),
        ],
      );

      expect(api.uploaded.length, 1);
      expect(api.uploaded.first, isNot(raw));
      expect(base64Encode(api.uploaded.first), isNot(base64Encode(raw)));

      final metadata = payload['metadata'] as List<dynamic>;
      final item = metadata.first as Map<String, dynamic>;
      expect(item['file_id'], 1001);

      final byUser = item['ciphertext_by_user'] as Map<String, dynamic>;
      expect(byUser.keys.toSet(), <String>{'7', '9'});

      final myCiphertext = byUser['7'] as String;
      final descriptorRaw = await signal.decrypt(
        peerUserId: 7,
        ciphertext: myCiphertext,
      );
      final descriptor = jsonDecode(descriptorRaw) as Map<String, dynamic>;
      expect(descriptor['signal_v2_attachment'], isTrue);
      expect(descriptor['file_id'], 1001);
      expect(descriptor['key'], isA<String>());
      expect(descriptor['nonce'], isA<String>());
    },
  );

  test(
    'decryptIncomingWsMessageFull keeps legacy base64 media payload support',
    () async {
      final api = _FakeChatsApi();
      final signal = _FakeSignalProtocolClient();
      final repo = ChatsRepository(api, signal);
      final raw = Uint8List.fromList(<int>[11, 22, 33, 44, 55]);
      final legacyCiphertext = await signal.encrypt(
        peerUserId: 7,
        plaintext: base64Encode(raw),
      );

      final decoded = await repo.decryptIncomingWsMessageFull(
        message: <String, dynamic>{
          'id': 501,
          'chat_id': 42,
          'sender_id': 9,
          'message_type': 'media',
          'message': jsonEncode(<String, dynamic>{
            'ciphertext_by_user': <String, dynamic>{
              '7': await signal.encrypt(peerUserId: 7, plaintext: 'caption'),
            },
          }),
          'metadata': <dynamic>[
            <String, dynamic>{
              'file_id': null,
              'filename': 'legacy.bin',
              'mimetype': 'application/octet-stream',
              'size': raw.length,
              'signal_ciphertext_by_user': <String, dynamic>{
                '7': legacyCiphertext,
              },
            },
          ],
        },
      );

      expect(decoded.attachments.length, 1);
      final localPath = decoded.attachments.first.localPath;
      final file = File(localPath);
      final restored = await file.readAsBytes();
      expect(restored, raw);
    },
  );

  test(
    'decrypt fallback does not reuse stale text when ciphertext hash mismatches',
    () async {
      final cache = ChatsLocalCache();
      await cache.writeDecryptedText(
        chatId: 42,
        messageId: 2,
        text: 'как у тебя дела?',
        ciphertextHash: base64Encode(utf8.encode('old_hash')),
      );

      final repo = ChatsRepository(
        _FakeChatsApi(),
        _FakeSignalProtocolClient(),
      );
      final text = await repo.decryptIncomingWsMessage(
        message: <String, dynamic>{
          'id': 2,
          'chat_id': 42,
          'sender_id': 9,
          'message_type': 'text',
          'message': jsonEncode(<String, dynamic>{
            'ciphertext_by_user': <String, dynamic>{
              '7': base64Encode(utf8.encode('broken_payload')),
            },
          }),
        },
      );

      expect(text, '[encrypted]');
    },
  );

  test('clearCache(includeMessages) removes decrypted text entries', () async {
    final cache = ChatsLocalCache();
    await cache.writeDecryptedText(
      chatId: 42,
      messageId: 11,
      text: 'hello',
      ciphertextHash: base64Encode(utf8.encode('hash1')),
    );
    final before = await cache.readDecryptedTextEntriesForChat(42);
    expect(before['11']?.text, 'hello');

    await cache.clearCache(
      includeChats: false,
      includeMedia: false,
      includeMessages: true,
    );
    final after = await cache.readDecryptedTextEntriesForChat(42);
    expect(after, isEmpty);
  });

  test('pending media upload task cache persists and removes by id', () async {
    final cache = ChatsLocalCache();
    final task = PendingMediaUploadTaskEntry(
      taskId: 'task_1',
      clientMessageId: '11111111-1111-4111-8111-111111111111',
      chatId: 42,
      chatKind: 'private',
      peerId: 9,
      wsType: 'send_message',
      caption: 'hello',
      replyToMessageId: null,
      createdAt: DateTime.now(),
      attachments: const <PendingMediaUploadAttachmentEntry>[
        PendingMediaUploadAttachmentEntry(
          localPath: '/tmp/media.bin',
          filename: 'media.bin',
          mimetype: 'application/octet-stream',
          sizeBytes: 7,
        ),
      ],
    );

    await cache.upsertPendingMediaUploadTask(task);
    final saved = await cache.readPendingMediaUploadTasksForChat(42);
    expect(saved.length, 1);
    expect(saved.first.taskId, 'task_1');
    expect(saved.first.clientMessageId, '11111111-1111-4111-8111-111111111111');

    await cache.removePendingMediaUploadTask('task_1');
    final after = await cache.readPendingMediaUploadTasksForChat(42);
    expect(after, isEmpty);
  });
}
