import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

class AttachmentEncryptionResult {
  final Uint8List ciphertext;
  final Uint8List key;
  final Uint8List nonce;
  final String plaintextSha256Base64;
  final String ciphertextSha256Base64;

  const AttachmentEncryptionResult({
    required this.ciphertext,
    required this.key,
    required this.nonce,
    required this.plaintextSha256Base64,
    required this.ciphertextSha256Base64,
  });
}

class AttachmentCipher {
  AttachmentCipher._();

  static final Cipher _cipher = AesGcm.with256bits();
  static const int keyLength = 32;
  static const int nonceLength = 12;
  static const int macLength = 16;

  static Future<AttachmentEncryptionResult> encrypt(Uint8List plaintext) async {
    final key = _randomBytes(keyLength);
    final nonce = _randomBytes(nonceLength);
    final secretKey = SecretKey(key);
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );

    final ciphertext = Uint8List.fromList(<int>[
      ...box.cipherText,
      ...box.mac.bytes,
    ]);

    return AttachmentEncryptionResult(
      ciphertext: ciphertext,
      key: key,
      nonce: nonce,
      plaintextSha256Base64: _sha256Base64(plaintext),
      ciphertextSha256Base64: _sha256Base64(ciphertext),
    );
  }

  static Future<Uint8List> decrypt({
    required Uint8List ciphertext,
    required Uint8List key,
    required Uint8List nonce,
  }) async {
    if (key.length != keyLength) {
      throw ArgumentError('Attachment key must be 32 bytes');
    }
    if (nonce.length != nonceLength) {
      throw ArgumentError('Attachment nonce must be 12 bytes');
    }
    if (ciphertext.length < macLength) {
      throw ArgumentError('Attachment ciphertext is too short');
    }

    final body = ciphertext.sublist(0, ciphertext.length - macLength);
    final macBytes = ciphertext.sublist(ciphertext.length - macLength);
    final box = SecretBox(body, nonce: nonce, mac: Mac(macBytes));
    final plain = await _cipher.decrypt(box, secretKey: SecretKey(key));
    return Uint8List.fromList(plain);
  }

  static Future<Uint8List> encryptChunk({
    required Uint8List plaintextChunk,
    required Uint8List key,
    required Uint8List baseNonce,
    required int chunkIndex,
  }) async {
    if (baseNonce.length != nonceLength) {
      throw ArgumentError('Attachment nonce must be 12 bytes');
    }
    final nonce = _deriveChunkNonce(baseNonce, chunkIndex);
    final box = await _cipher.encrypt(
      plaintextChunk,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    return Uint8List.fromList(<int>[...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Uint8List> decryptChunk({
    required Uint8List ciphertextChunk,
    required Uint8List key,
    required Uint8List baseNonce,
    required int chunkIndex,
  }) async {
    if (baseNonce.length != nonceLength) {
      throw ArgumentError('Attachment nonce must be 12 bytes');
    }
    if (ciphertextChunk.length < macLength) {
      throw ArgumentError('Attachment ciphertext chunk too short');
    }
    final nonce = _deriveChunkNonce(baseNonce, chunkIndex);
    final body = ciphertextChunk.sublist(0, ciphertextChunk.length - macLength);
    final mac = ciphertextChunk.sublist(ciphertextChunk.length - macLength);
    final plain = await _cipher.decrypt(
      SecretBox(body, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key),
    );
    return Uint8List.fromList(plain);
  }

  static String toBase64(Uint8List bytes) => base64Encode(bytes);

  static Uint8List fromBase64(String value) =>
      Uint8List.fromList(base64Decode(value));

  static String sha256Base64(Uint8List data) => _sha256Base64(data);

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final out = Uint8List(length);
    for (var i = 0; i < out.length; i++) {
      out[i] = random.nextInt(256);
    }
    return out;
  }

  static String _sha256Base64(Uint8List data) =>
      base64Encode(sha256.convert(data).bytes);

  static Uint8List _deriveChunkNonce(Uint8List baseNonce, int chunkIndex) {
    if (chunkIndex < 0) {
      throw ArgumentError('chunkIndex must be >= 0');
    }
    final out = Uint8List.fromList(baseNonce);
    out[8] = (chunkIndex >> 24) & 0xff;
    out[9] = (chunkIndex >> 16) & 0xff;
    out[10] = (chunkIndex >> 8) & 0xff;
    out[11] = chunkIndex & 0xff;
    return out;
  }
}
