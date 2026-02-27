/// Ratchet Session
///
/// Управление сессией Double Ratchet для шифрования/расшифровки сообщений
/// Использует FFI bindings из RenSdk

import 'dart:convert';
import 'dart:typed_data';
import '../../sdk/ren_sdk.dart';

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
/// 
/// Сериализуемое состояние сессии Double Ratchet
/// Включает identity keys для восстановления сессии
class RatchetSessionState {
  final String sessionId;
  
  // Identity keys для сохранения сессии
  final String localIdentityPublic;
  final String localIdentityPrivate;
  final String? remoteIdentityPublic;
  final String? remoteIdentityPrivate;
  
  // Root key
  final String rootKey;
  
  // Symmetric ratchet state
  final String? sendingChainKey;
  final int? sendingCounter;
  final String? receivingChainKey;
  final int? receivingCounter;
  final int sentMessageCount;
  final int receivedMessageCount;
  
  // DH ratchet state
  final String localRatchetKey;
  final String? remoteRatchetKey;
  
  final int createdAt;

  RatchetSessionState({
    required this.sessionId,
    required this.localIdentityPublic,
    required this.localIdentityPrivate,
    this.remoteIdentityPublic,
    this.remoteIdentityPrivate,
    required this.rootKey,
    this.sendingChainKey,
    this.sendingCounter,
    this.receivingChainKey,
    this.receivingCounter,
    this.sentMessageCount = 0,
    this.receivedMessageCount = 0,
    required this.localRatchetKey,
    this.remoteRatchetKey,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'localIdentityPublic': localIdentityPublic,
      'localIdentityPrivate': localIdentityPrivate,
      'remoteIdentityPublic': remoteIdentityPublic,
      'remoteIdentityPrivate': remoteIdentityPrivate,
      'rootKey': rootKey,
      'sendingChainKey': sendingChainKey,
      'sendingCounter': sendingCounter,
      'receivingChainKey': receivingChainKey,
      'receivingCounter': receivingCounter,
      'sentMessageCount': sentMessageCount,
      'receivedMessageCount': receivedMessageCount,
      'localRatchetKey': localRatchetKey,
      'remoteRatchetKey': remoteRatchetKey,
      'createdAt': createdAt,
    };
  }

  factory RatchetSessionState.fromJson(Map<String, dynamic> json) {
    return RatchetSessionState(
      sessionId: json['sessionId'] as String,
      localIdentityPublic: json['localIdentityPublic'] as String,
      localIdentityPrivate: json['localIdentityPrivate'] as String,
      remoteIdentityPublic: json['remoteIdentityPublic'] as String?,
      remoteIdentityPrivate: json['remoteIdentityPrivate'] as String?,
      rootKey: json['rootKey'] as String,
      sendingChainKey: json['sendingChainKey'] as String?,
      sendingCounter: json['sendingCounter'] as int?,
      receivingChainKey: json['receivingChainKey'] as String?,
      receivingCounter: json['receivingCounter'] as int?,
      sentMessageCount: json['sentMessageCount'] as int? ?? 0,
      receivedMessageCount: json['receivedMessageCount'] as int? ?? 0,
      localRatchetKey: json['localRatchetKey'] as String,
      remoteRatchetKey: json['remoteRatchetKey'] as String?,
      createdAt: json['createdAt'] as int,
    );
  }
}

/// Ratchet Session Manager
/// 
/// Использует Ren-SDK FFI для шифрования/расшифровки
class RatchetSession {
  RatchetSession._();

  /// Инициализация как Alice (initiator)
  /// 
  /// [sharedSecret] - Shared secret от X3DH в base64
  /// [localIdentityKey] - Локальный identity public key (base64)
  /// [remoteIdentityKey] - Remote identity public key (base64)
  static Future<RatchetSessionState> initiate({
    required String sharedSecret,
    required String localIdentityKey,
    required String remoteIdentityKey,
  }) async {
    final sdk = RenSdk.instance;
    
    final stateJson = sdk.ratchetInitiate(
      sharedSecretB64: sharedSecret,
      localIdentityPublic: localIdentityKey,
      remoteIdentityPublic: remoteIdentityKey,
    );

    if (stateJson == null) {
      throw Exception('Ratchet initiate failed');
    }

    final state = Map<String, dynamic>.from(jsonDecode(stateJson));
    return RatchetSessionState.fromJson(state);
  }

  /// Инициализация как Bob (respondent)
  /// 
  /// [sharedSecret] - Shared secret от X3DH в base64
  /// [localIdentityKey] - Локальный identity public key (base64)
  /// [remoteIdentityKey] - Remote identity public key (base64)
  /// [remoteRatchetKey] - Remote ratchet public key (ephemeral от Alice)
  static Future<RatchetSessionState> respond({
    required String sharedSecret,
    required String localIdentityKey,
    required String remoteIdentityKey,
    required String remoteRatchetKey,
  }) async {
    final sdk = RenSdk.instance;
    
    final stateJson = sdk.ratchetRespond(
      sharedSecretB64: sharedSecret,
      localIdentityPublic: localIdentityKey,
      remoteIdentityPublic: remoteIdentityKey,
      remoteRatchetKey: remoteRatchetKey,
    );

    if (stateJson == null) {
      throw Exception('Ratchet respond failed');
    }

    final state = Map<String, dynamic>.from(jsonDecode(stateJson));
    return RatchetSessionState.fromJson(state);
  }

  /// Шифрование сообщения
  /// 
  /// Возвращает RatchetMessage и обновлённое состояние сессии
  static Future<({RatchetMessage message, RatchetSessionState newState})> encryptMessage({
    required RatchetSessionState session,
    required Uint8List plaintext,
  }) async {
    final sdk = RenSdk.instance;
    
    final plaintextB64 = base64Encode(plaintext);
    final sessionJson = jsonEncode(session.toJson());
    
    final resultJson = sdk.ratchetEncrypt(
      sessionStateJson: sessionJson,
      plaintext: plaintextB64,
    );

    if (resultJson == null) {
      throw Exception('Ratchet encrypt failed');
    }

    final result = Map<String, dynamic>.from(jsonDecode(resultJson));
    final messageJson = result['message'] as Map<String, dynamic>;
    final newStateJson = result['session_state'] as Map<String, dynamic>;

    return (
      message: RatchetMessage.fromJson(Map<String, dynamic>.from(messageJson)),
      newState: RatchetSessionState.fromJson(Map<String, dynamic>.from(newStateJson)),
    );
  }

  /// Расшифровка сообщения
  /// 
  /// Возвращает расшифрованные данные и обновлённое состояние сессии
  static Future<({Uint8List plaintext, RatchetSessionState newState})> decryptMessage({
    required RatchetSessionState session,
    required RatchetMessage message,
  }) async {
    final sdk = RenSdk.instance;
    
    final sessionJson = jsonEncode(session.toJson());
    final messageJson = message.toJson();
    
    final resultJson = sdk.ratchetDecrypt(
      sessionStateJson: sessionJson,
      message: messageJson,
    );

    if (resultJson == null) {
      throw Exception('Ratchet decrypt failed');
    }

    final result = Map<String, dynamic>.from(jsonDecode(resultJson));
    final plaintextB64 = result['plaintext'] as String;
    final newStateJson = result['session_state'] as Map<String, dynamic>;

    return (
      plaintext: base64Decode(plaintextB64),
      newState: RatchetSessionState.fromJson(Map<String, dynamic>.from(newStateJson)),
    );
  }
}
