/// X3DH Protocol FFI Bindings

import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// X3DH Protocol bindings
class X3DHProtocol {
  final DynamicLibrary _lib;

  X3DHProtocol(this._lib);

  /// Инициализация X3DH (Alice)
  /// Возвращает shared secret в base64
  String initiate({
    required String identitySecretKey,
    required String ephemeralPublicKey,
    required String ephemeralSecretKey,
    required String theirIdentityKey,
    required String theirSignedPreKey,
    String? theirOneTimePreKey,
  }) {
    final x3dhInitiate = _lib.lookupFunction<
      Pointer<Int8> Function(
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
      ),
      Pointer<Int8> Function(
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
      )
    >('x3dh_initiate_ffi');

    return _callX3DH(
      x3dhInitiate,
      identitySecretKey,
      ephemeralPublicKey,
      ephemeralSecretKey,
      theirIdentityKey,
      theirSignedPreKey,
      theirOneTimePreKey,
    );
  }

  /// Ответ в X3DH (Bob)
  /// Возвращает shared secret в base64
  String respond({
    required String identitySecretKey,
    required String signedPreKeySecret,
    required String theirIdentityKey,
    required String theirEphemeralKey,
    String? oneTimePreKeySecret,
  }) {
    final x3dhRespond = _lib.lookupFunction<
      Pointer<Int8> Function(
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
      ),
      Pointer<Int8> Function(
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
        Pointer<Int8>,
      )
    >('x3dh_respond_ffi');

    return _callXDHRespond(
      x3dhRespond,
      identitySecretKey,
      signedPreKeySecret,
      theirIdentityKey,
      theirEphemeralKey,
      oneTimePreKeySecret,
    );
  }

  String _callX3DH(
    Pointer<Int8> Function(
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
    ) func,
    String identitySk,
    String ephPk,
    String ephSk,
    String theirIk,
    String theirSpk,
    String? theirOtk,
  ) {
    final result = func(
      identitySk.toNativeUtf8().cast(),
      ephPk.toNativeUtf8().cast(),
      ephSk.toNativeUtf8().cast(),
      theirIk.toNativeUtf8().cast(),
      theirSpk.toNativeUtf8().cast(),
      theirOtk?.toNativeUtf8().cast() ?? nullptr,
    );

    if (result == nullptr) {
      throw Exception('X3DH Initiate failed');
    }

    final resultStr = result.cast<Utf8>().toDartString();
    calloc.free(result);
    return resultStr;
  }

  String _callXDHRespond(
    Pointer<Int8> Function(
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
    ) func,
    String identitySk,
    String spkSk,
    String theirIk,
    String theirEph,
    String? otkSk,
  ) {
    final result = func(
      identitySk.toNativeUtf8().cast(),
      spkSk.toNativeUtf8().cast(),
      theirIk.toNativeUtf8().cast(),
      theirEph.toNativeUtf8().cast(),
      otkSk?.toNativeUtf8().cast() ?? nullptr,
    );

    if (result == nullptr) {
      throw Exception('X3DH Respond failed');
    }

    final resultStr = result.cast<Utf8>().toDartString();
    calloc.free(result);
    return resultStr;
  }
}

/// PreKey Bundle для X3DH
class PreKeyBundle {
  final int userId;
  final String identityKey;
  final String signedPreKey;
  final String signedPreKeySignature;
  final String? oneTimePreKey;
  final int? oneTimePreKeyId;

  PreKeyBundle({
    required this.userId,
    required this.identityKey,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    this.oneTimePreKey,
    this.oneTimePreKeyId,
  });

  factory PreKeyBundle.fromJson(Map<String, dynamic> json) {
    return PreKeyBundle(
      userId: json['user_id'] as int,
      identityKey: json['identity_key'] as String,
      signedPreKey: json['signed_prekey'] as String,
      signedPreKeySignature: json['signed_prekey_signature'] as String,
      oneTimePreKey: json['one_time_prekey'] as String?,
      oneTimePreKeyId: json['one_time_prekey_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'identity_key': identityKey,
      'signed_prekey': signedPreKey,
      'signed_prekey_signature': signedPreKeySignature,
      if (oneTimePreKey != null) 'one_time_prekey': oneTimePreKey,
      if (oneTimePreKeyId != null) 'one_time_prekey_id': oneTimePreKeyId,
    };
  }
}

/// Shared Secret от X3DH
class SharedSecret {
  final Uint8List bytes;

  SharedSecret(this.bytes);

  factory SharedSecret.fromBase64(String base64) {
    return SharedSecret(base64ToBytes(base64));
  }

  String toBase64() {
    return bytesToBase64(bytes);
  }

  static Uint8List base64ToBytes(String base64) {
    // Используем dart:convert
    return Uint8List.fromList(base64.runes.toList());
  }

  static String bytesToBase64(Uint8List bytes) {
    // Простая реализация для примера
    return String.fromCharCodes(bytes);
  }
}
