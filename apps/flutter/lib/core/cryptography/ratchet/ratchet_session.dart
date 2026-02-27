/// Ratchet Session
/// 
/// Управление сессией Double Ratchet для шифрования/расшифровки сообщений

import 'dart:typed_data';

/// Encrypted Message с заголовком
class RatchetMessage {
  final String ephemeralKey;
  final String ciphertext;
  final int counter;

  RatchetMessage({
    required this.ephemeralKey,
    required this.ciphertext,
    required this.counter,
  });

  factory RatchetMessage.fromJson(Map<String, dynamic> json) {
    return RatchetMessage(
      ephemeralKey: json['ephemeral_key'] as String,
      ciphertext: json['ciphertext'] as String,
      counter: json['counter'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ephemeral_key': ephemeralKey,
      'ciphertext': ciphertext,
      'counter': counter,
    };
  }
}

/// Ratchet Session State
class RatchetSessionState {
  final String sessionId;
  final String rootKey;
  final String? sendingChainKey;
  final int? sendingCounter;
  final String? receivingChainKey;
  final int? receivingCounter;
  final String localRatchetKey;
  final String? remoteRatchetKey;
  final int createdAt;

  RatchetSessionState({
    required this.sessionId,
    required this.rootKey,
    this.sendingChainKey,
    this.sendingCounter,
    this.receivingChainKey,
    this.receivingCounter,
    required this.localRatchetKey,
    this.remoteRatchetKey,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'rootKey': rootKey,
      'sendingChainKey': sendingChainKey,
      'sendingCounter': sendingCounter,
      'receivingChainKey': receivingChainKey,
      'receivingCounter': receivingCounter,
      'localRatchetKey': localRatchetKey,
      'remoteRatchetKey': remoteRatchetKey,
      'createdAt': createdAt,
    };
  }

  factory RatchetSessionState.fromJson(Map<String, dynamic> json) {
    return RatchetSessionState(
      sessionId: json['sessionId'] as String,
      rootKey: json['rootKey'] as String,
      sendingChainKey: json['sendingChainKey'] as String?,
      sendingCounter: json['sendingCounter'] as int?,
      receivingChainKey: json['receivingChainKey'] as String?,
      receivingCounter: json['receivingCounter'] as int?,
      localRatchetKey: json['localRatchetKey'] as String,
      remoteRatchetKey: json['remoteRatchetKey'] as String?,
      createdAt: json['createdAt'] as int,
    );
  }
}

/// Ratchet Session Manager
/// Пока заглушка - будет реализовано после добавления FFI в Ren-SDK
class RatchetSession {
  /// Инициализация как Alice (initiator)
  static Future<RatchetSessionState> initiate({
    required String sharedSecret,
    required String localIdentityKey,
    required String remoteIdentityKey,
  }) {
    throw UnimplementedError('Ratchet FFI ещё не реализован в Ren-SDK');
  }

  /// Инициализация как Bob (respondent)
  static Future<RatchetSessionState> respond({
    required String sharedSecret,
    required String localIdentityKey,
    required String remoteIdentityKey,
    required String remoteRatchetKey,
  }) {
    throw UnimplementedError('Ratchet FFI ещё не реализован в Ren-SDK');
  }

  /// Шифрование сообщения
  static Future<RatchetMessage> encryptMessage({
    required RatchetSessionState session,
    required Uint8List plaintext,
  }) {
    throw UnimplementedError('Ratchet FFI ещё не реализован в Ren-SDK');
  }

  /// Расшифровка сообщения
  static Future<Uint8List> decryptMessage({
    required RatchetSessionState session,
    required RatchetMessage message,
  }) {
    throw UnimplementedError('Ratchet FFI ещё не реализован в Ren-SDK');
  }
}
