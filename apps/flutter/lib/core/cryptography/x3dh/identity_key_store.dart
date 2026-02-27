/// Identity Key Store
/// 
/// Хранит и управляет Identity Keys пользователя

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

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

/// Identity Key Store — хранит Identity Keys в защищённом хранилище
class IdentityKeyStore {
  final FlutterSecureStorage _storage;
  static const String _identityKey = 'identity_key_pair';
  static const String _signedPreKey = 'signed_prekey';
  static const String _signedPreKeySignature = 'signed_prekey_signature';
  static const String _keyVersion = 'key_version';

  IdentityKeyStore() : _storage = const FlutterSecureStorage();

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
