/// E2EE Service для 1:1 чатов с Double Ratchet
///
/// Интегрирует X3DH + Double Ratchet для шифрования/расшифровки сообщений
/// с Forward Secrecy и Post-Compromise Security

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:ren/core/cryptography/x3dh/identity_key_store.dart';
import 'package:ren/core/cryptography/x3dh/prekey_repository.dart';
import 'package:ren/core/cryptography/ratchet/ratchet_session.dart';
import 'package:ren/core/cryptography/ratchet/session_store.dart';
import 'package:ren/core/sdk/ren_sdk.dart';

/// E2EE Service для 1:1 чатов
class ChatE2EEService {
  final RenSdk _sdk;
  final IdentityKeyStore _identityKeyStore;
  final PreKeyRepository _prekeyRepo;
  final SessionStore _sessionStore;

  ChatE2EEService({
    required PreKeyRepository prekeyRepo,
    required SessionStore sessionStore,
  })  : _sdk = RenSdk.instance,
        _identityKeyStore = IdentityKeyStore(),
        _prekeyRepo = prekeyRepo,
        _sessionStore = sessionStore;

  /// Инициализация E2EE для пользователя
  Future<void> initialize() async {
    await _sdk.initialize();
    await _identityKeyStore.initialize();
  }

  /// Получить мой identity public key
  Future<String> getMyIdentityPublicKey() async {
    final keys = await _identityKeyStore.getIdentityKeys();
    return keys.publicKey;
  }

  /// Инициализация E2EE для отправки сообщения (Alice)
  /// 
  /// 1. Получаем PreKey Bundle получателя
  /// 2. Выполняем X3DH key exchange
  /// 3. Инициализируем Double Ratchet сессию
  /// 4. Сохраняем сессию
  Future<void> initializeOutboundSession({
    required int recipientId,
  }) async {
    // Проверяем есть ли уже сессия
    final existingSession = await _sessionStore.getSession('user_$recipientId');
    if (existingSession != null) {
      return; // Сессия уже существует
    }

    // 1. Получаем PreKey Bundle получателя
    final bundle = await _prekeyRepo.getBundle(recipientId);

    // 2. Получаем мои identity keys
    final myIdentityKeys = await _identityKeyStore.getIdentityKeys();

    // 3. Генерируем ephemeral key pair
    final ephemeralKeys = _sdk.generateKeyPair()!;

    // 4. Выполняем X3DH Initiate (Alice)
    final sharedSecret = _sdk.x3dhInitiate(
      identitySecretKey: myIdentityKeys.privateKey,
      ephemeralPublicKey: ephemeralKeys['public_key']!,
      ephemeralSecretKey: ephemeralKeys['private_key']!,
      theirIdentityKey: bundle.identityKey,
      theirSignedPreKey: bundle.signedPreKey,
      theirOneTimePreKey: bundle.oneTimePreKey,
    );

    if (sharedSecret == null) {
      throw Exception('X3DH Initiate failed');
    }

    // 5. Инициализируем Double Ratchet
    final sessionState = await RatchetSession.initiate(
      sharedSecret: sharedSecret,
      localIdentityKey: myIdentityKeys.publicKey,
      remoteIdentityKey: bundle.identityKey,
    );

    // 6. Сохраняем сессию
    await _sessionStore.storeSession('user_$recipientId', sessionState);

    // 7. Помечаем OTPK как использованный
    if (bundle.oneTimePreKeyId != null) {
      await _prekeyRepo.consumePreKey(bundle.oneTimePreKeyId!);
    }
  }

  /// Инициализация E2EE для получения сообщения (Bob)
  /// 
  /// 1. Получаем identity key отправителя
  /// 2. Выполняем X3DH Respond
  /// 3. Инициализируем Double Ratchet сессию
  /// 4. Сохраняем сессию
  Future<void> initializeInboundSession({
    required int senderId,
    required String senderIdentityKey,
    required String senderEphemeralKey,
  }) async {
    // Проверяем есть ли уже сессия
    final existingSession = await _sessionStore.getSession('user_$senderId');
    if (existingSession != null) {
      return; // Сессия уже существует
    }

    // 1. Получаем мои identity keys
    final myIdentityKeys = await _identityKeyStore.getIdentityKeys();

    // 2. Получаем мой signed prekey
    final signedPreKey = await _identityKeyStore.getSignedPreKey();
    if (signedPreKey == null) {
      throw Exception('No signed prekey found');
    }

    // 3. Выполняем X3DH Respond (Bob)
    final sharedSecret = _sdk.x3dhRespond(
      identitySecretKey: myIdentityKeys.privateKey,
      signedPreKeySecret: signedPreKey.privateKey,
      theirIdentityKey: senderIdentityKey,
      theirEphemeralKey: senderEphemeralKey,
    );

    if (sharedSecret == null) {
      throw Exception('X3DH Respond failed');
    }

    // 4. Инициализируем Double Ratchet
    final sessionState = await RatchetSession.respond(
      sharedSecret: sharedSecret,
      localIdentityKey: myIdentityKeys.publicKey,
      remoteIdentityKey: senderIdentityKey,
      remoteRatchetKey: senderEphemeralKey,
    );

    // 5. Сохраняем сессию
    await _sessionStore.storeSession('user_$senderId', sessionState);
  }

  /// Зашифровать сообщение для 1:1 чата
  /// 
  /// Возвращает зашифрованное сообщение в формате для отправки на сервер
  Future<Map<String, dynamic>> encryptMessage({
    required int chatId,
    required String plaintext,
    required int recipientId,
  }) async {
    // Инициализируем сессию если нужно
    await initializeOutboundSession(recipientId: recipientId);

    // Получаем сессию
    final sessionState = await _sessionStore.getSession('user_$recipientId');
    if (sessionState == null) {
      throw Exception('Session not found for user_$recipientId');
    }

    // Шифруем сообщение
    final result = await RatchetSession.encryptMessage(
      session: sessionState,
      plaintext: Uint8List.fromList(plaintext.utf8Encode()),
    );

    // Сохраняем обновлённую сессию
    await _sessionStore.storeSession('user_$recipientId', result.newState);

    // Возвращаем зашифрованное сообщение в формате API
    return {
      'kind': 'private',
      'protocol_version': 2,
      'message_type': 'ratchet_message',
      'body': jsonEncode({
        'ephemeral_key': result.message.ephemeralKey,
        'ciphertext': result.message.ciphertext,
        'counter': result.message.counter,
      }),
      'chat_id': chatId,
      'sender_identity_key': sessionState.localIdentityPublic,
    };
  }

  /// Расшифровать сообщение из 1:1 чата
  /// 
  /// Принимает зашифрованное сообщение и возвращает plaintext
  Future<String> decryptMessage({
    required int chatId,
    required Map<String, dynamic> messageData,
    required int senderId,
  }) async {
    final protocolVersion = messageData['protocol_version'] as int?;
    
    // Поддержка legacy сообщений
    if (protocolVersion == null || protocolVersion == 1) {
      return messageData['body'] as String? ?? '';
    }

    // Получаем зашифрованное сообщение из body
    final bodyJson = messageData['body'] as String?;
    if (bodyJson == null) {
      throw Exception('No body in message');
    }

    final messageJson = jsonDecode(bodyJson) as Map<String, dynamic>;
    final ratchetMessage = RatchetMessage(
      ephemeralKey: messageJson['ephemeral_key'] as String,
      ciphertext: messageJson['ciphertext'] as String,
      counter: messageJson['counter'] as int,
    );

    // Получаем sender identity key
    final senderIdentityKey = messageData['sender_identity_key'] as String?;
    if (senderIdentityKey == null) {
      throw Exception('No sender identity key');
    }

    // Инициализируем сессию если нужно
    await initializeInboundSession(
      senderId: senderId,
      senderIdentityKey: senderIdentityKey,
      senderEphemeralKey: ratchetMessage.ephemeralKey,
    );

    // Получаем сессию
    final sessionState = await _sessionStore.getSession('user_$senderId');
    if (sessionState == null) {
      throw Exception('Session not found for user_$senderId');
    }

    // Расшифровываем сообщение
    final result = await RatchetSession.decryptMessage(
      session: sessionState,
      message: ratchetMessage,
    );

    // Сохраняем обновлённую сессию
    await _sessionStore.storeSession('user_$senderId', result.newState);

    // Возвращаем plaintext
    return String.fromCharCodes(result.plaintext);
  }

  /// Проверка что чат является 1:1 private
  bool isPrivateChat(String chatKind, int? userId) {
    return chatKind.trim().toLowerCase() == 'private' && userId != null;
  }

  /// Получить статус E2EE для чата
  Future<E2EEStatus> getChatE2EEStatus({
    required String chatKind,
    required int? userId,
  }) async {
    if (!isPrivateChat(chatKind, userId)) {
      return E2EEStatus.notAvailable;
    }

    // Проверяем есть ли активная сессия
    if (userId != null) {
      final session = await _sessionStore.getSession('user_$userId');
      if (session != null) {
        return E2EEStatus.enabled;
      }
    }

    return E2EEStatus.available;
  }

  /// Синхронизировать PreKeys
  Future<void> syncPreKeys() async {
    final myUserId = 1; // TODO: Получить из auth service
    
    await _prekeyRepo.syncPreKeys(
      userId: myUserId,
      generatePreKeys: _generatePreKeys,
      minCount: 50,
      maxCount: 100,
    );
  }

  /// Сгенерировать новые One-Time PreKeys
  Future<List<OneTimePreKey>> _generatePreKeys() async {
    final preKeys = <OneTimePreKey>[];
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    for (int i = 0; i < 50; i++) {
      final keyPair = _sdk.generateKeyPair()!;
      preKeys.add(OneTimePreKey(
        prekeyId: timestamp + i,
        prekey: keyPair['public_key']!,
      ));
    }
    
    return preKeys;
  }

  /// Освободить ресурсы
  void dispose() {
    // _sdk не закрываем - это singleton
  }
}

/// E2EE статус чата
enum E2EEStatus {
  /// E2EE доступно и активно
  enabled,

  /// E2EE доступно но не активно
  available,

  /// E2EE недоступно (групповой чат или канал)
  notAvailable,
}

extension E2EEStatusExtension on E2EEStatus {
  String get label {
    switch (this) {
      case E2EEStatus.enabled:
        return 'E2EE Enabled';
      case E2EEStatus.available:
        return 'E2EE Available';
      case E2EEStatus.notAvailable:
        return 'E2EE Not Available';
    }
  }

  bool get isEnabled => this == E2EEStatus.enabled;
  bool get isAvailable => this == E2EEStatus.enabled || this == E2EEStatus.available;
}

/// Extension для String
extension Utf8Encode on String {
  List<int> utf8Encode() => utf8.encoder.convert(this);
}
