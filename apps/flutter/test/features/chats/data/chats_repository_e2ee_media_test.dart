import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      Keys.userId: '7',
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
      final file = File(decoded.attachments.first.localPath!);
      final restored = await file.readAsBytes();
      expect(restored, raw);
    },
  );
}
