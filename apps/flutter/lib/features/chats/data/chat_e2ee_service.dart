/// E2EE Service для 1:1 чатов
/// 
/// Интегрирует шифрование/расшифровку сообщений в чаты

import 'package:ren/core/cryptography/crypto_service.dart';
import 'package:ren/core/cryptography/x3dh/identity_key_store.dart';

/// E2EE Service для 1:1 чатов
class ChatE2EEService {
  final CryptoService _cryptoService;
  final IdentityKeyStore _identityKeyStore;
  
  ChatE2EEService({
    required CryptoService cryptoService,
  })  : _cryptoService = cryptoService,
        _identityKeyStore = IdentityKeyStore();

  /// Инициализация E2EE для пользователя
  Future<void> initialize() async {
    await _cryptoService.initialize();
  }

  /// Проверка что чат является 1:1 private
  bool isPrivateChat(String chatKind, int? userId) {
    return chatKind.trim().toLowerCase() == 'private' && userId != null;
  }

  /// Зашифровать сообщение для 1:1 чата
  Future<Map<String, dynamic>> encryptMessage({
    required int chatId,
    required String plaintext,
    required int recipientId,
  }) async {
    // Пока используем существующее шифрование из RenSdk
    // TODO: Интегрировать Double Ratchet
    
    // Для демонстрации — просто возвращаем plaintext
    // В реальности здесь будет вызов:
    // final encrypted = await _cryptoService.encryptMessage(
    //   recipientId: recipientId,
    //   plaintext: plaintext,
    // );
    
    return {
      'kind': 'private',
      'body': plaintext, // Пока без шифрования
      'chat_id': chatId,
    };
  }

  /// Расшифровать сообщение из 1:1 чата
  Future<String> decryptMessage({
    required int chatId,
    required Map<String, dynamic> messageData,
    required int senderId,
  }) async {
    // Пока используем существующее шифрование из RenSdk
    // TODO: Интегрировать Double Ratchet
    
    final body = messageData['body'] as String?;
    if (body == null) return '';
    
    // Для демонстрации — просто возвращаем body
    // В реальности здесь будет вызов:
    // final decrypted = await _cryptoService.decryptMessage(
    //   senderId: senderId,
    //   message: encrypted,
    // );
    
    return body;
  }

  /// Получить статус E2EE для чата
  E2EEStatus getChatE2EEStatus({
    required String chatKind,
    required int? userId,
  }) {
    if (!isPrivateChat(chatKind, userId)) {
      return E2EEStatus.notAvailable;
    }
    
    // TODO: Проверить есть ли активная сессия
    return E2EEStatus.available;
  }

  /// Освободить ресурсы
  void dispose() {
    _cryptoService.dispose();
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
