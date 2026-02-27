/// Crypto Service
/// 
/// Высокоуровневый API для шифрования/расшифровки сообщений

import 'x3dh/identity_key_store.dart';
import 'x3dh/prekey_repository.dart';
import 'x3dh/x3dh_protocol.dart';
import 'ratchet/ratchet_session.dart';
import 'ratchet/session_store.dart';

/// Crypto Service Exception
class CryptoException implements Exception {
  final String message;
  final dynamic originalError;

  CryptoException(this.message, [this.originalError]);

  @override
  String toString() => 'CryptoException: $message${originalError != null ? ' ($originalError)' : ''}';
}

/// Crypto Service
class CryptoService {
  final IdentityKeyStore _identityKeyStore;
  final PreKeyRepository _preKeyRepository;
  final SessionStore _sessionStore;

  CryptoService({
    required PreKeyRepository preKeyRepository,
    required SessionStore sessionStore,
  })  : _identityKeyStore = IdentityKeyStore(),
        _preKeyRepository = preKeyRepository,
        _sessionStore = sessionStore;

  /// Инициализация криптографии
  /// Генерирует Identity Keys если их нет
  Future<void> initialize() async {
    var identityKeys = await _identityKeyStore.loadIdentityKeyPair();
    
    if (identityKeys == null) {
      // TODO: Сгенерировать новые Identity Keys через FFI
      throw CryptoException('Identity Keys generation not yet implemented via FFI');
    }
  }

  /// Получить PreKey Bundle другого пользователя
  Future<PreKeyBundle> getPreKeyBundle(int userId) async {
    return await _preKeyRepository.getBundle(userId);
  }

  /// Начать сессию с пользователем (Alice)
  Future<void> startSession({
    required int recipientId,
    required PreKeyBundle bundle,
  }) async {
    // TODO: Реализовать X3DH + Ratchet через FFI
    throw CryptoException('Session initiation not yet implemented via FFI');
  }

  /// Зашифровать сообщение
  Future<RatchetMessage> encryptMessage({
    required int recipientId,
    required String plaintext,
  }) async {
    // TODO: Реализовать шифрование через FFI
    throw CryptoException('Message encryption not yet implemented via FFI');
  }

  /// Расшифровать сообщение
  Future<String> decryptMessage({
    required int senderId,
    required RatchetMessage message,
  }) async {
    // TODO: Реализовать расшифровку через FFI
    throw CryptoException('Message decryption not yet implemented via FFI');
  }

  /// Загрузить One-Time PreKeys на сервер
  Future<void> uploadPreKeys(List<OneTimePreKey> prekeys) async {
    await _preKeyRepository.uploadOneTimePreKeys(prekeys);
  }

  /// Загрузить Signed PreKey на сервер
  Future<void> uploadSignedPreKey(String prekey, String signature) async {
    await _preKeyRepository.uploadSignedPreKey(prekey, signature);
  }

  /// Освободить ресурсы
  void dispose() {
    _preKeyRepository.dispose();
  }
}
