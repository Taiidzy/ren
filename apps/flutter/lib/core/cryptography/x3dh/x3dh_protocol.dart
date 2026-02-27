/// X3DH Protocol Helpers
///
/// Использует Ren-SDK FFI bindings для X3DH протокола

import 'dart:convert';
import 'dart:typed_data';

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
    return SharedSecret(base64Decode(base64));
  }

  String toBase64() {
    return base64Encode(bytes);
  }
}
