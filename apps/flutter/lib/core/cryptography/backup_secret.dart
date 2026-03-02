import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int _pbkdf2Iterations = 210000;
const int _backupSecretLength = 32;

Future<String> deriveSignalBackupSecretBase64({
  required String password,
  required String salt,
}) async {
  if (password.trim().isEmpty || salt.trim().isEmpty) {
    throw ArgumentError('password and salt are required');
  }
  final secret = _pbkdf2HmacSha256(
    password: Uint8List.fromList(utf8.encode(password)),
    salt: Uint8List.fromList(utf8.encode(salt)),
    iterations: _pbkdf2Iterations,
    keyLength: _backupSecretLength,
  );
  return base64Encode(secret);
}

Uint8List _pbkdf2HmacSha256({
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int keyLength,
}) {
  if (iterations <= 0 || keyLength <= 0) {
    throw ArgumentError('iterations and keyLength must be > 0');
  }
  final hLen = 32;
  final blockCount = (keyLength + hLen - 1) ~/ hLen;
  final out = Uint8List(blockCount * hLen);
  final hmac = Hmac(sha256, password);

  for (var block = 1; block <= blockCount; block++) {
    final blockIndex = ByteData(4)..setUint32(0, block, Endian.big);
    final init = BytesBuilder(copy: false)
      ..add(salt)
      ..add(blockIndex.buffer.asUint8List());
    var u = Uint8List.fromList(hmac.convert(init.toBytes()).bytes);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < hLen; j++) {
        t[j] ^= u[j];
      }
    }
    out.setRange((block - 1) * hLen, block * hLen, t);
  }

  return Uint8List.sublistView(out, 0, keyLength);
}
