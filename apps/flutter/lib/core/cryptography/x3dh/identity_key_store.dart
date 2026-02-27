/// Identity Key Store
///
/// Хранит и управляет Identity Keys пользователя

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ren/core/sdk/ren_sdk.dart';

/// Identity Key Pair
class IdentityKeyPair {
  final String publicKey;
  final String privateKey;
  final String signaturePublicKey;
  final String signaturePrivateKey;

  IdentityKeyPair({
    required this.publicKey,
    required this.privateKey,
    required this.signaturePublicKey,
    required this.signaturePrivateKey,
  });

  Map<String, dynamic> toJson() {
    return {
      'publicKey': publicKey,
      'privateKey': privateKey,
      'signaturePublicKey': signaturePublicKey,
      'signaturePrivateKey': signaturePrivateKey,
    };
  }

  factory IdentityKeyPair.fromJson(Map<String, dynamic> json) {
    return IdentityKeyPair(
      publicKey: json['publicKey'] as String,
      privateKey: json['privateKey'] as String,
      signaturePublicKey: json['signaturePublicKey'] as String,
      signaturePrivateKey: json['signaturePrivateKey'] as String,
    );
  }
}

/// Signed PreKey с подписью
class SignedPreKey {
  final String publicKey;
  final String privateKey;
  final String signature;

  SignedPreKey({
    required this.publicKey,
    required this.privateKey,
    required this.signature,
  });
}

/// Identity Key Store — хранит Identity Keys в защищённом хранилище
class IdentityKeyStore {
  final FlutterSecureStorage _storage;
  final RenSdk _sdk;
  static const String _identityKey = 'identity_key_pair';
  static const String _signedPreKey = 'signed_prekey';
  static const String _signedPreKeySignature = 'signed_prekey_signature';
  static const String _keyVersion = 'key_version';

  IdentityKeyStore()
      : _storage = const FlutterSecureStorage(),
        _sdk = RenSdk.instance;

  /// Инициализация
  Future<void> initialize() async {
    // Проверяем есть ли ключи
    final existing = await loadIdentityKeyPair();
    if (existing == null) {
      // Генерируем новые
      await generateIdentityKeys();
    }
  }

  /// Сгенерировать новые Identity Keys
  Future<IdentityKeyPair> generateIdentityKeys() async {
    // Генерируем Ed25519 identity key pair
    final identityKeys = _sdk.generateIdentityKeyPair();
    if (identityKeys == null) {
      throw Exception('Failed to generate identity key pair');
    }

    // Генерируем X25519 key pair для identity
    final x25519Keys = _sdk.generateKeyPair()!;

    // Подписываем X25519 public key
    final signature = _sdk.signPublicKey(
      x25519PublicKeyB64: x25519Keys['public_key']!,
      identityPrivateKeyB64: identityKeys['privateKey']!,
      keyVersion: 1,
    );

    if (signature == null) {
      throw Exception('Failed to sign public key');
    }

    final keyPair = IdentityKeyPair(
      publicKey: x25519Keys['public_key']!,
      privateKey: x25519Keys['private_key']!,
      signaturePublicKey: identityKeys['publicKey']!,
      signaturePrivateKey: identityKeys['privateKey']!,
    );

    await saveIdentityKeyPair(keyPair);
    await saveKeyVersion(1);

    return keyPair;
  }

  /// Сохранить Identity Key Pair
  Future<void> saveIdentityKeyPair(IdentityKeyPair keys) async {
    final json = jsonEncode(keys.toJson());
    await _storage.write(key: _identityKey, value: json);
  }

  /// Загрузить Identity Key Pair
  Future<IdentityKeyPair?> loadIdentityKeyPair() async {
    final jsonStr = await _storage.read(key: _identityKey);
    if (jsonStr == null) return null;

    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return IdentityKeyPair.fromJson(json);
  }

  /// Получить Identity Keys (загружает или генерирует)
  Future<IdentityKeyPair> getIdentityKeys() async {
    var keys = await loadIdentityKeyPair();
    if (keys == null) {
      keys = await generateIdentityKeys();
    }
    return keys;
  }

  /// Сохранить Signed PreKey
  Future<void> saveSignedPreKey(String preKey, String signature) async {
    await _storage.write(key: _signedPreKey, value: preKey);
    await _storage.write(key: _signedPreKeySignature, value: signature);
  }

  /// Загрузить Signed PreKey
  Future<Map<String, String>?> loadSignedPreKey() async {
    final preKey = await _storage.read(key: _signedPreKey);
    final signature = await _storage.read(key: _signedPreKeySignature);

    if (preKey == null || signature == null) return null;

    return {
      'preKey': preKey,
      'signature': signature,
    };
  }

  /// Получить Signed PreKey (загружает или генерирует)
  Future<SignedPreKey?> getSignedPreKey() async {
    var data = await loadSignedPreKey();
    if (data == null) {
      // Генерируем новый signed prekey
      final x25519Keys = _sdk.generateKeyPair()!;
      final identityKeys = await getIdentityKeys();

      final signature = _sdk.signPublicKey(
        x25519PublicKeyB64: x25519Keys['public_key']!,
        identityPrivateKeyB64: identityKeys.signaturePrivateKey,
        keyVersion: 1,
      );

      if (signature == null) {
        return null;
      }

      await saveSignedPreKey(x25519Keys['private_key']!, signature);
      
      data = {
        'preKey': x25519Keys['private_key']!,
        'signature': signature,
      };
    }

    return SignedPreKey(
      publicKey: data['preKey']!,
      privateKey: data['preKey']!,
      signature: data['signature']!,
    );
  }

  /// Сохранить версию ключа
  Future<void> saveKeyVersion(int version) async {
    await _storage.write(key: _keyVersion, value: version.toString());
  }

  /// Загрузить версию ключа
  Future<int> loadKeyVersion() async {
    final versionStr = await _storage.read(key: _keyVersion);
    if (versionStr == null) return 1;
    return int.parse(versionStr);
  }

  /// Очистить все ключи
  Future<void> clear() async {
    await _storage.delete(key: _identityKey);
    await _storage.delete(key: _signedPreKey);
    await _storage.delete(key: _signedPreKeySignature);
    await _storage.delete(key: _keyVersion);
  }
}
