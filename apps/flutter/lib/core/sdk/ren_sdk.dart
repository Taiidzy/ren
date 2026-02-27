// ignore_for_file: non_constant_identifier_names, camel_case_types, unintended_html_in_doc_comment

import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform, File, Directory;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'package:logger/logger.dart';

const String _ffiTag = 'RenFFI';

/// Dart FFI bindings for the Rust SDK exported in ffi.rs.
/// This file wraps all exported functions in a safe Dart API.

final DynamicLibrary _dylib = _openLibrary();
final Logger _logger = Logger();

DynamicLibrary _openLibrary() {
  try {
    if (Platform.isAndroid) {
      final lib = DynamicLibrary.open('libren_sdk.so');
      _logger.i("Android SDK Loaded");
      return lib;
    } else if (Platform.isIOS) {
      final lib = DynamicLibrary.process();
      _logger.i("iOS SDK Loaded");
      return lib;
    } else if (Platform.isMacOS) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final cwd = Directory.current.path;
      final candidates = <String>[
        'libren_sdk.dylib',
        '$exeDir/libren_sdk.dylib',
        '$cwd/libren_sdk.dylib',
        '$exeDir/../Resources/libren_sdk.dylib',
        '$exeDir/../Frameworks/libren_sdk.dylib',
        '$exeDir/Frameworks/libren_sdk.dylib',
      ];
      for (final c in candidates) {
        try {
          final lib = DynamicLibrary.open(c);
          _logger.i("macOS SDK Loaded");
          return lib;
        } catch (_) {}
      }
      throw ArgumentError('libren_sdk.dylib not found');
    } else if (Platform.isLinux) {
      final lib = DynamicLibrary.open('libren_sdk.so');
      _logger.i("Linux SDK Loaded");
      return lib;
    } else if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final cwd = Directory.current.path;
      final candidates = <String>[
        'ren_sdk.dll',
        '$exeDir/ren_sdk.dll',
        '$cwd/ren_sdk.dll',
      ];
      for (final c in candidates) {
        try {
          final lib = DynamicLibrary.open(c);
          _logger.i("Windows SDK Loaded");
          return lib;
        } catch (e) {
          _logger.e(e);
        }
      }
      throw ArgumentError('ren_sdk.dll not found');
    }
    throw UnsupportedError('Platform not supported');
  } catch (e, st) {
    e;
    st;
    rethrow;
  }
}

/* ============================
   Native struct definitions (C repr)
   ============================ */

// Note: names here match Rust struct fields (repr(C))
final class RenKeyPair extends Struct {
  external Pointer<Utf8> public_key;
  external Pointer<Utf8> private_key;
}

final class RenEncryptedMessage extends Struct {
  external Pointer<Utf8> ciphertext;
  external Pointer<Utf8> nonce;
}

final class RenEncryptedFile extends Struct {
  external Pointer<Utf8> ciphertext;
  external Pointer<Utf8> nonce;
  external Pointer<Utf8> filename;
  external Pointer<Utf8> mimetype;
}

final class RenWrappedKey extends Struct {
  external Pointer<Utf8> wrapped_key;
  external Pointer<Utf8> ephemeral_public_key;
  external Pointer<Utf8> nonce;
}

final class RenDecryptedFile extends Struct {
  external Pointer<Uint8> data;
  // pointer-sized integer (usize). Use IntPtr for portability.
  @IntPtr()
  external int len;
  external Pointer<Utf8> filename;
  external Pointer<Utf8> mimetype;
  external Pointer<Utf8> message;
}

// P0-4: RatchetMessage structure (matches Rust RatchetMessage)
final class RenRatchetMessage extends Struct {
  external Pointer<Utf8> ephemeral_key;
  external Pointer<Utf8> ciphertext;
  @Int32()
  external int counter;
}

/* ============================
   Native function typedefs
   (we map all functions exported in ffi.rs)
   ============================ */

// Free helpers
typedef ren_free_string_native = Void Function(Pointer<Utf8>);
typedef ren_free_bytes_native = Void Function(Pointer<Uint8>, IntPtr);

// Free wrappers (struct-based)
typedef ren_free_key_pair_native = Void Function(RenKeyPair);
typedef ren_free_encrypted_message_native = Void Function(RenEncryptedMessage);
typedef ren_free_encrypted_file_native = Void Function(RenEncryptedFile);
typedef ren_free_wrapped_key_native = Void Function(RenWrappedKey);
typedef ren_free_decrypted_file_native = Void Function(RenDecryptedFile);

// Simple string returns
typedef ren_generate_nonce_native = Pointer<Utf8> Function();
typedef ren_generate_salt_native = Pointer<Utf8> Function();

// struct return
typedef ren_generate_key_pair_native = RenKeyPair Function();

// message key
typedef ren_generate_message_key_native = Pointer<Utf8> Function();

// derive
typedef ren_derive_key_from_password_native =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef ren_derive_key_from_string_native =
    Pointer<Utf8> Function(Pointer<Utf8>);

// encrypt/decrypt data (strings -> returns base64 string)
typedef ren_encrypt_data_native =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef ren_decrypt_data_native =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);

// messages -> struct or string
typedef ren_encrypt_message_native =
    RenEncryptedMessage Function(Pointer<Utf8>, Pointer<Utf8>);
typedef ren_decrypt_message_native =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef ren_decrypt_message_with_key_bytes_native =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Uint8>,
      IntPtr,
    );

// file encrypt/decrypt
typedef ren_encrypt_file_native =
    RenEncryptedFile Function(
      Pointer<Uint8>,
      IntPtr,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef ren_decrypt_file_native =
    Pointer<Uint8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<IntPtr>,
    );

typedef ren_decrypt_file_raw_native =
    Pointer<Uint8> Function(
      Pointer<Uint8>,
      IntPtr,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<IntPtr>,
    );

typedef ren_decrypt_file_raw_with_key_bytes_native =
    Pointer<Uint8> Function(
      Pointer<Uint8>,
      IntPtr,
      Pointer<Utf8>,
      Pointer<Uint8>,
      IntPtr,
      Pointer<IntPtr>,
    );

// wrap / unwrap
typedef ren_wrap_symmetric_key_native =
    RenWrappedKey Function(Pointer<Utf8>, Pointer<Utf8>);
typedef ren_unwrap_symmetric_key_native =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );

typedef ren_unwrap_symmetric_key_bytes_native =
    Pointer<Uint8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<IntPtr>,
    );

// P0-3: Argon2id Recovery KDF native typedefs
typedef ren_derive_recovery_key_argon2id_native =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
// Temporarily disabled due to FFI type compatibility issues
// typedef ren_generate_recovery_salt_native =
//     Pointer<Utf8> Function(Int32);
// typedef ren_validate_recovery_entropy_native =
//     Int32 Function(Pointer<Utf8>);

// --- Dart-side typedefs (для lookupFunction second generic) ---
typedef ren_free_string_dart = void Function(Pointer<Utf8>);
typedef ren_free_bytes_dart = void Function(Pointer<Uint8>, int);
typedef ren_free_key_pair_dart = void Function(RenKeyPair);
typedef ren_free_encrypted_message_dart = void Function(RenEncryptedMessage);
typedef ren_free_encrypted_file_dart = void Function(RenEncryptedFile);
typedef ren_free_wrapped_key_dart = void Function(RenWrappedKey);
typedef ren_free_decrypted_file_dart = void Function(RenDecryptedFile);

typedef ren_generate_nonce_dart = Pointer<Utf8> Function();
typedef ren_generate_salt_dart = Pointer<Utf8> Function();
typedef ren_generate_key_pair_dart = RenKeyPair Function();
typedef ren_generate_message_key_dart = Pointer<Utf8> Function();
typedef ren_derive_key_from_password_dart =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef ren_derive_key_from_string_dart = Pointer<Utf8> Function(Pointer<Utf8>);

// P0-3: Argon2id Recovery KDF typedefs
typedef ren_derive_recovery_key_argon2id_dart =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
// Temporarily disabled due to FFI type compatibility issues
// typedef ren_generate_recovery_salt_dart =
//     Pointer<Utf8> Function(Int32);
// typedef ren_validate_recovery_entropy_dart =
//     Int32 Function(Pointer<Utf8>);

// P0-2: Ed25519 Identity Key typedefs
final class RenIdentityKeyPair extends Struct {
  external Pointer<Utf8> public_key;
  external Pointer<Utf8> private_key;
}

typedef ren_generate_identity_key_pair_native = RenIdentityKeyPair Function();
typedef ren_sign_public_key_native =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef ren_verify_signed_public_key_native =
    Int32 Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
    );

typedef ren_generate_identity_key_pair_dart = RenIdentityKeyPair Function();
typedef ren_sign_public_key_dart =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef ren_verify_signed_public_key_dart =
    int Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
    );

typedef ren_encrypt_data_dart =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef ren_decrypt_data_dart =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef ren_encrypt_message_dart =
    RenEncryptedMessage Function(Pointer<Utf8>, Pointer<Utf8>);
typedef ren_decrypt_message_dart =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef ren_decrypt_message_with_key_bytes_dart =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint8>, int);
typedef ren_encrypt_file_dart =
    RenEncryptedFile Function(
      Pointer<Uint8>,
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef ren_decrypt_file_dart =
    Pointer<Uint8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<IntPtr>,
    );

typedef ren_decrypt_file_raw_dart =
    Pointer<Uint8> Function(
      Pointer<Uint8>,
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<IntPtr>,
    );

typedef ren_decrypt_file_raw_with_key_bytes_dart =
    Pointer<Uint8> Function(
      Pointer<Uint8>,
      int,
      Pointer<Utf8>,
      Pointer<Uint8>,
      int,
      Pointer<IntPtr>,
    );
typedef ren_wrap_symmetric_key_dart =
    RenWrappedKey Function(Pointer<Utf8>, Pointer<Utf8>);
typedef ren_unwrap_symmetric_key_dart =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );

typedef ren_unwrap_symmetric_key_bytes_dart =
    Pointer<Uint8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<IntPtr>,
    );

// P0-4: X3DH & Double Ratchet typedefs
typedef x3dh_initiate_native = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef x3dh_respond_native = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef ratchet_initiate_native = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef ratchet_respond_native = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef ratchet_encrypt_native = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef ratchet_decrypt_native = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef x3dh_initiate_dart = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef x3dh_respond_dart = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef ratchet_initiate_dart = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef ratchet_respond_dart = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef ratchet_encrypt_dart = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);

typedef ratchet_decrypt_dart = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);

// ==============================
// Lookup native functions
// ==============================

final ren_free_string = _dylib
    .lookupFunction<ren_free_string_native, ren_free_string_dart>(
      'ren_free_string',
    );
final ren_free_bytes = _dylib
    .lookupFunction<ren_free_bytes_native, ren_free_bytes_dart>(
      'ren_free_bytes',
    );

final ren_free_key_pair = _dylib
    .lookupFunction<ren_free_key_pair_native, ren_free_key_pair_dart>(
      'ren_free_key_pair',
    );
final ren_free_encrypted_message = _dylib
    .lookupFunction<
      ren_free_encrypted_message_native,
      ren_free_encrypted_message_dart
    >('ren_free_encrypted_message');
final ren_free_encrypted_file = _dylib
    .lookupFunction<
      ren_free_encrypted_file_native,
      ren_free_encrypted_file_dart
    >('ren_free_encrypted_file');
final ren_free_wrapped_key = _dylib
    .lookupFunction<ren_free_wrapped_key_native, ren_free_wrapped_key_dart>(
      'ren_free_wrapped_key',
    );
final ren_free_decrypted_file = _dylib
    .lookupFunction<
      ren_free_decrypted_file_native,
      ren_free_decrypted_file_dart
    >('ren_free_decrypted_file');

final _ren_generate_nonce = _dylib
    .lookupFunction<ren_generate_nonce_native, ren_generate_nonce_dart>(
      'ren_generate_nonce',
    );
final _ren_generate_salt = _dylib
    .lookupFunction<ren_generate_salt_native, ren_generate_salt_dart>(
      'ren_generate_salt',
    );
final _ren_generate_key_pair = _dylib
    .lookupFunction<ren_generate_key_pair_native, ren_generate_key_pair_dart>(
      'ren_generate_key_pair',
    );
final _ren_generate_message_key = _dylib
    .lookupFunction<
      ren_generate_message_key_native,
      ren_generate_message_key_dart
    >('ren_generate_message_key');

final _ren_derive_key_from_password = _dylib
    .lookupFunction<
      ren_derive_key_from_password_native,
      ren_derive_key_from_password_dart
    >('ren_derive_key_from_password');
final _ren_derive_key_from_string = _dylib
    .lookupFunction<
      ren_derive_key_from_string_native,
      ren_derive_key_from_string_dart
    >('ren_derive_key_from_string');

// P0-3: Argon2id Recovery KDF FFI lookups
final _ren_derive_recovery_key_argon2id = _dylib
    .lookupFunction<
      ren_derive_recovery_key_argon2id_native,
      ren_derive_recovery_key_argon2id_dart
    >('ren_derive_recovery_key_argon2id');
// Temporarily disabled due to FFI type compatibility issues
// final _ren_generate_recovery_salt = _dylib
//     .lookupFunction<
//       ren_generate_recovery_salt_native,
//       ren_generate_recovery_salt_dart
//     >('ren_generate_recovery_salt');
// final _ren_validate_recovery_entropy = _dylib
//     .lookupFunction<
//       ren_validate_recovery_entropy_native,
//       ren_validate_recovery_entropy_dart
//     >('ren_validate_recovery_entropy');

// P0-2: Ed25519 Identity Key FFI lookups
final _ren_generate_identity_key_pair = _dylib
    .lookupFunction<
      ren_generate_identity_key_pair_native,
      ren_generate_identity_key_pair_dart
    >('ren_generate_identity_key_pair');
final _ren_sign_public_key = _dylib
    .lookupFunction<ren_sign_public_key_native, ren_sign_public_key_dart>(
      'ren_sign_public_key',
    );
final _ren_verify_signed_public_key = _dylib
    .lookupFunction<
      ren_verify_signed_public_key_native,
      ren_verify_signed_public_key_dart
    >('ren_verify_signed_public_key');

final _ren_encrypt_data = _dylib
    .lookupFunction<ren_encrypt_data_native, ren_encrypt_data_dart>(
      'ren_encrypt_data',
    );
final _ren_decrypt_data = _dylib
    .lookupFunction<ren_decrypt_data_native, ren_decrypt_data_dart>(
      'ren_decrypt_data',
    );

final _ren_encrypt_message = _dylib
    .lookupFunction<ren_encrypt_message_native, ren_encrypt_message_dart>(
      'ren_encrypt_message',
    );
final _ren_decrypt_message = _dylib
    .lookupFunction<ren_decrypt_message_native, ren_decrypt_message_dart>(
      'ren_decrypt_message',
    );

final _ren_decrypt_message_with_key_bytes = _dylib
    .lookupFunction<
      ren_decrypt_message_with_key_bytes_native,
      ren_decrypt_message_with_key_bytes_dart
    >('ren_decrypt_message_with_key_bytes');

final _ren_encrypt_file = _dylib
    .lookupFunction<ren_encrypt_file_native, ren_encrypt_file_dart>(
      'ren_encrypt_file',
    );
final _ren_decrypt_file = _dylib
    .lookupFunction<ren_decrypt_file_native, ren_decrypt_file_dart>(
      'ren_decrypt_file',
    );

final _ren_decrypt_file_raw = _dylib
    .lookupFunction<ren_decrypt_file_raw_native, ren_decrypt_file_raw_dart>(
      'ren_decrypt_file_raw',
    );

final _ren_decrypt_file_raw_with_key_bytes = _dylib
    .lookupFunction<
      ren_decrypt_file_raw_with_key_bytes_native,
      ren_decrypt_file_raw_with_key_bytes_dart
    >('ren_decrypt_file_raw_with_key_bytes');

final _ren_wrap_symmetric_key = _dylib
    .lookupFunction<ren_wrap_symmetric_key_native, ren_wrap_symmetric_key_dart>(
      'ren_wrap_symmetric_key',
    );
final _ren_unwrap_symmetric_key = _dylib
    .lookupFunction<
      ren_unwrap_symmetric_key_native,
      ren_unwrap_symmetric_key_dart
    >('ren_unwrap_symmetric_key');

final _ren_unwrap_symmetric_key_bytes = _dylib
    .lookupFunction<
      ren_unwrap_symmetric_key_bytes_native,
      ren_unwrap_symmetric_key_bytes_dart
    >('ren_unwrap_symmetric_key_bytes');

// P0-4: X3DH & Double Ratchet FFI lookups
final _x3dh_initiate = _dylib
    .lookupFunction<x3dh_initiate_native, x3dh_initiate_dart>(
      'x3dh_initiate_ffi',
    );
final _x3dh_respond = _dylib
    .lookupFunction<x3dh_respond_native, x3dh_respond_dart>(
      'x3dh_respond_ffi',
    );
final _ratchet_initiate = _dylib
    .lookupFunction<ratchet_initiate_native, ratchet_initiate_dart>(
      'ratchet_initiate_ffi',
    );
final _ratchet_respond = _dylib
    .lookupFunction<ratchet_respond_native, ratchet_respond_dart>(
      'ratchet_respond_ffi',
    );
final _ratchet_encrypt = _dylib
    .lookupFunction<ratchet_encrypt_native, ratchet_encrypt_dart>(
      'ratchet_encrypt_ffi',
    );
final _ratchet_decrypt = _dylib
    .lookupFunction<ratchet_decrypt_native, ratchet_decrypt_dart>(
      'ratchet_decrypt_ffi',
    );

// ==============================
// High-level Dart wrapper
// ==============================

class RenSdk {
  RenSdk();

  RenSdk._private();
  static final RenSdk instance = RenSdk._private();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Инициализирует SDK.
  /// Выполняет лёгкую проверку доступности нативной библиотеки.
  /// Вызывать один раз при старте приложения.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    try {
      // Smoke-check native bindings early, so runtime failures are explicit.
      final nonce = generateNonce();
      if (nonce.isEmpty) {
        throw StateError('Ren SDK smoke-check failed: empty nonce');
      }

      _initialized = true;
    } catch (e, st) {
      _logger.e('Ren SDK initialize failed', error: e, stackTrace: st);
      throw StateError('Ren SDK initialize failed: $e');
    }
  }

  Uint8List? unwrapSymmetricKeyBytes(
    String wrappedB64,
    String ephemeralPublicKeyB64,
    String nonceB64,
    String receiverPrivateKeyB64,
  ) {
    try {
      return using((arena) {
        final pw = wrappedB64.toNativeUtf8(allocator: arena);
        final peph = ephemeralPublicKeyB64.toNativeUtf8(allocator: arena);
        final pn = nonceB64.toNativeUtf8(allocator: arena);
        final pr = receiverPrivateKeyB64.toNativeUtf8(allocator: arena);
        final outLenPtr = arena.allocate<IntPtr>(sizeOf<IntPtr>());

        final dataPtr = _ren_unwrap_symmetric_key_bytes(
          pw,
          peph,
          pn,
          pr,
          outLenPtr,
        );
        if (dataPtr == nullptr) {
          return null;
        }

        final len = outLenPtr.value;
        final dataList = dataPtr.asTypedList(len);
        final out = Uint8List.fromList(dataList);
        ren_free_bytes(dataPtr, len);
        return out;
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<Uint8List?> decryptFileBytesRawWithKeyBytes(
    Uint8List ciphertextBytes,
    String nonceB64,
    Uint8List keyBytes,
  ) async {
    try {
      if (ciphertextBytes.isEmpty || keyBytes.isEmpty) {
        return null;
      }

      return using((arena) {
        final ctPtr = arena.allocate<Uint8>(ciphertextBytes.length);
        ctPtr.asTypedList(ciphertextBytes.length).setAll(0, ciphertextBytes);

        final kPtr = arena.allocate<Uint8>(keyBytes.length);
        kPtr.asTypedList(keyBytes.length).setAll(0, keyBytes);

        final pn = nonceB64.toNativeUtf8(allocator: arena);
        final outLenPtr = arena.allocate<IntPtr>(sizeOf<IntPtr>());

        final dataPtr = _ren_decrypt_file_raw_with_key_bytes(
          ctPtr,
          ciphertextBytes.length,
          pn,
          kPtr,
          keyBytes.length,
          outLenPtr,
        );

        if (dataPtr == nullptr) {
          return null;
        }

        final len = outLenPtr.value;
        final dataList = dataPtr.asTypedList(len);
        final bytesOut = Uint8List.fromList(dataList);
        ren_free_bytes(dataPtr, len);
        return bytesOut;
      });
    } catch (e) {
      rethrow;
    }
  }

  /* ======= Low-level helpers ======= */

  String _readAndFreeString(Pointer<Utf8> p) {
    try {
      if (p == nullptr) {
        return '';
      }
      final s = p.toDartString();
      ren_free_string(p);
      return s;
    } catch (e) {
      rethrow;
    }
  }

  String _ptrToDartAndFree(Pointer<Utf8> p) {
    try {
      final s = _readAndFreeString(p);
      return s;
    } catch (e) {
      rethrow;
    }
  }

  /// Шифрует строку `data` симметричным ключом `keyB64` (оба в UTF-8, ключ — base64).
  /// Возвращает base64-строку с шифртекстом или null при ошибке.
  /// Используйте для быстрой симметричной шифрации небольших данных.
  String? encryptData(String data, String keyB64) {
    try {
      return using((arena) {
        final pd = data.toNativeUtf8(allocator: arena);
        final pk = keyB64.toNativeUtf8(allocator: arena);
        final pres = _ren_encrypt_data(pd, pk);
        if (pres == nullptr) {
          return null;
        }
        final res = pres.toDartString();
        ren_free_string(pres);
        return res;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Расшифровывает base64-строку `b64cipher` симметричным ключом `keyB64` (base64).
  /// Возвращает исходную строку или null при ошибке/несовпадении ключа.
  String? decryptData(String b64cipher, String keyB64) {
    try {
      return using((arena) {
        final pc = b64cipher.toNativeUtf8(allocator: arena);
        final pk = keyB64.toNativeUtf8(allocator: arena);
        final pres = _ren_decrypt_data(pc, pk);
        if (pres == nullptr) {
          return null;
        }
        final res = pres.toDartString();
        ren_free_string(pres);
        return res;
      });
    } catch (e) {
      rethrow;
    }
  }

  // ==============================
  // P0-3: Argon2id Recovery KDF Methods
  // ==============================

  /// P0-3: Derive a recovery key using Argon2id (memory-hard KDF).
  ///
  /// This function derives a 32-byte key from a recovery phrase/secret using
  /// Argon2id with OWASP-recommended parameters (64 MiB memory, 3 iterations,
  /// parallelism 4).
  ///
  /// # Arguments
  /// * `recoverySecret` - Recovery phrase or high-entropy secret (>= 128 bits)
  /// * `saltB64` - Unique salt encoded as Base64
  ///
  /// # Returns
  /// Base64-encoded 32-byte key, or null on error.
  String? deriveRecoveryKeyArgon2id(String recoverySecret, String saltB64) {
    try {
      return using((arena) {
        final pSecret = recoverySecret.toNativeUtf8(allocator: arena);
        final pSalt = saltB64.toNativeUtf8(allocator: arena);
        final pResult = _ren_derive_recovery_key_argon2id(pSecret, pSalt);
        if (pResult == nullptr) {
          return null;
        }
        final result = pResult.toDartString();
        ren_free_string(pResult);
        return result;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// P0-3: Generate a secure random salt for recovery KDF.
  ///
  /// # Arguments
  /// * `sizeBytes` - Size of salt in bytes (minimum 16, default 16)
  ///
  /// # Returns
  /// Base64-encoded salt, or null on error.
  // Temporarily disabled due to FFI type compatibility issues
  // String? generateRecoverySalt([int sizeBytes = 16]) {
  //   try {
  //     final size = sizeBytes < 16 ? 16 : sizeBytes;
  //     final pResult = _ren_generate_recovery_salt(size);
  //     if (pResult == nullptr) {
  //       return null;
  //     }
  //     final result = pResult.toDartString();
  //     ren_free_string(pResult);
  //     return result;
  //   } catch (e) {
  //     rethrow;
  //   }
  // }

  /// P0-3: Validate that a recovery phrase has sufficient entropy.
  ///
  /// Checks if the recovery phrase has at least 128 bits of entropy.
  ///
  /// # Arguments
  /// * `recoveryPhrase` - Recovery phrase to validate
  ///
  /// # Returns
  /// `true` if valid (>= 128 bits), `false` otherwise.
  // Temporarily disabled due to FFI type compatibility issues
  // bool validateRecoveryEntropy(String recoveryPhrase) {
  //   try {
  //     return using((arena) {
  //       final pPhrase = recoveryPhrase.toNativeUtf8(allocator: arena);
  //       final result = _ren_validate_recovery_entropy(pPhrase);
  //       return result == 1;
  //     });
  //   } catch (e) {
  //     rethrow;
  //   }
  // }

  // ==============================
  // P0-2: Ed25519 Identity Key Methods
  // ==============================

  /// P0-2: Generate an Ed25519 identity key pair for signing.
  ///
  /// The identity key is used to sign X25519 public keys for authentication,
  /// preventing MITM attacks through key substitution.
  ///
  /// # Returns
  /// Map with `publicKey` and `privateKey` (both Base64-encoded), or null on error.
  Map<String, String>? generateIdentityKeyPair() {
    try {
      final result = _ren_generate_identity_key_pair();
      if (result.public_key == nullptr || result.private_key == nullptr) {
        return null;
      }
      final publicKey = result.public_key.toDartString();
      final privateKey = result.private_key.toDartString();
      ren_free_string(result.public_key);
      ren_free_string(result.private_key);
      return {'publicKey': publicKey, 'privateKey': privateKey};
    } catch (e) {
      rethrow;
    }
  }

  /// P0-2: Sign an X25519 public key with Ed25519 identity key.
  ///
  /// Creates a cryptographic signature that binds the X25519 public key
  /// to the identity key, preventing MITM attacks.
  ///
  /// # Arguments
  /// * `x25519PublicKeyB64` - X25519 public key to sign (Base64)
  /// * `identityPrivateKeyB64` - Ed25519 private key for signing (Base64)
  /// * `keyVersion` - Version number for key rotation support
  ///
  /// # Returns
  /// Base64-encoded signature, or null on error.
  String? signPublicKey({
    required String x25519PublicKeyB64,
    required String identityPrivateKeyB64,
    required int keyVersion,
  }) {
    try {
      return using((arena) {
        final pPk = x25519PublicKeyB64.toNativeUtf8(allocator: arena);
        final pIdKey = identityPrivateKeyB64.toNativeUtf8(allocator: arena);
        final pResult = _ren_sign_public_key(pPk, pIdKey, keyVersion);
        if (pResult == nullptr) {
          return null;
        }
        final result = pResult.toDartString();
        ren_free_string(pResult);
        return result;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// P0-2: Verify a signed X25519 public key.
  ///
  /// Verifies that the signature was created by the holder of the identity
  /// private key, ensuring the public key hasn't been tampered with.
  ///
  /// # Arguments
  /// * `publicKeyB64` - X25519 public key (Base64)
  /// * `signatureB64` - Ed25519 signature (Base64)
  /// * `identityPublicKeyB64` - Ed25519 public key for verification (Base64)
  /// * `keyVersion` - Key version to verify
  ///
  /// # Returns
  /// `true` if signature is valid, `false` otherwise.
  bool verifySignedPublicKey({
    required String publicKeyB64,
    required String signatureB64,
    required String identityPublicKeyB64,
    required int keyVersion,
  }) {
    try {
      return using((arena) {
        final pPk = publicKeyB64.toNativeUtf8(allocator: arena);
        final pSig = signatureB64.toNativeUtf8(allocator: arena);
        final pIdPk = identityPublicKeyB64.toNativeUtf8(allocator: arena);
        final pVersion = arena.allocate<Int32>(sizeOf<Int32>())
          ..value = keyVersion;
        final result = _ren_verify_signed_public_key(
          pPk,
          pSig,
          pIdPk,
          Pointer.fromAddress(pVersion.address),
          keyVersion,
        );
        return result == 1;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Шифрует сообщение и возвращает карту с полями `ciphertext` (base64) и `nonce` (base64).
  /// Параметры: `message` (строка) и `keyB64` (симметричный ключ base64).
  Map<String, String>? encryptMessage(String message, String keyB64) {
    try {
      return using((arena) {
        final pm = message.toNativeUtf8(allocator: arena);
        final pk = keyB64.toNativeUtf8(allocator: arena);
        final resStruct = _ren_encrypt_message(pm, pk);

        if (resStruct.ciphertext == nullptr) {
          return null;
        }
        final ct = _readAndFreeString(resStruct.ciphertext);
        final nonce = _readAndFreeString(resStruct.nonce);
        return {'ciphertext': ct, 'nonce': nonce};
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Расшифровывает сообщение по `ciphertextB64` (base64), `nonceB64` (base64) и `keyB64` (base64).
  /// Возвращает исходный текст или null при ошибке.
  String? decryptMessage(String ciphertextB64, String nonceB64, String keyB64) {
    try {
      return using((arena) {
        final pc = ciphertextB64.toNativeUtf8(allocator: arena);
        final pn = nonceB64.toNativeUtf8(allocator: arena);
        final pk = keyB64.toNativeUtf8(allocator: arena);
        final pres = _ren_decrypt_message(pc, pn, pk);
        if (pres == nullptr) {
          return null;
        }
        final res = pres.toDartString();
        ren_free_string(pres);
        return res;
      });
    } catch (e) {
      rethrow;
    }
  }

  String? decryptMessageWithKeyBytes(
    String ciphertextB64,
    String nonceB64,
    Uint8List keyBytes,
  ) {
    try {
      if (keyBytes.isEmpty) return null;

      return using((arena) {
        final pc = ciphertextB64.toNativeUtf8(allocator: arena);
        final pn = nonceB64.toNativeUtf8(allocator: arena);
        final kPtr = arena.allocate<Uint8>(keyBytes.length);
        kPtr.asTypedList(keyBytes.length).setAll(0, keyBytes);

        final pres = _ren_decrypt_message_with_key_bytes(
          pc,
          pn,
          kPtr,
          keyBytes.length,
        );
        if (pres == nullptr) {
          return null;
        }
        final res = pres.toDartString();
        ren_free_string(pres);
        return res;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Шифрует файл (массив байт) и возвращает карту с метаданными:
  /// `ciphertext` (base64), `nonce` (base64), `filename`, `mimetype`.
  /// Используйте для отправки зашифрованных вложений.
  Map<String, String>? encryptFileSync(
    Uint8List bytes,
    String filename,
    String mimetype,
    String keyB64,
  ) {
    try {
      return using((arena) {
        final dataPtr = arena.allocate<Uint8>(bytes.length);
        dataPtr.asTypedList(bytes.length).setAll(0, bytes);

        final pFilename = filename.toNativeUtf8(allocator: arena);
        final pMimetype = mimetype.toNativeUtf8(allocator: arena);
        final pKey = keyB64.toNativeUtf8(allocator: arena);

        final res = _ren_encrypt_file(
          dataPtr,
          bytes.length,
          pFilename,
          pMimetype,
          pKey,
        );

        if (res.ciphertext == nullptr) {
          return null;
        }
        final ciphertext = _readAndFreeString(res.ciphertext);
        final nonce = _readAndFreeString(res.nonce);
        final fname = _readAndFreeString(res.filename);
        final mime = _readAndFreeString(res.mimetype);

        return {
          'ciphertext': ciphertext,
          'nonce': nonce,
          'filename': fname,
          'mimetype': mime,
        };
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, String>?> encryptFile(
    Uint8List bytes,
    String filename,
    String mimetype,
    String keyB64,
  ) async {
    return encryptFileSync(bytes, filename, mimetype, keyB64);
  }

  /// Расшифровывает файл: принимает зашифрованные байты и метаданные.
  /// Возвращает карту: `data` (Uint8List), `filename`, `mimetype`, `message` (если присутствует).
  Future<Uint8List?> decryptFileBytes(
    String ciphertextB64,
    String nonceB64,
    String keyB64,
  ) async {
    try {
      return using((arena) {
        final pc = ciphertextB64.toNativeUtf8(allocator: arena);
        final pn = nonceB64.toNativeUtf8(allocator: arena);
        final pk = keyB64.toNativeUtf8(allocator: arena);
        final outLenPtr = arena.allocate<IntPtr>(sizeOf<IntPtr>());

        final dataPtr = _ren_decrypt_file(pc, pn, pk, outLenPtr);
        if (dataPtr == nullptr) {
          return null;
        }

        final len = outLenPtr.value;
        final dataList = dataPtr.asTypedList(len);
        final bytesOut = Uint8List.fromList(dataList);
        ren_free_bytes(dataPtr, len);
        return bytesOut;
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<Uint8List?> decryptFileBytesRaw(
    Uint8List ciphertextBytes,
    String nonceB64,
    String keyB64,
  ) async {
    try {
      if (ciphertextBytes.isEmpty) {
        return null;
      }

      return using((arena) {
        final ctPtr = arena.allocate<Uint8>(ciphertextBytes.length);
        ctPtr.asTypedList(ciphertextBytes.length).setAll(0, ciphertextBytes);

        final pn = nonceB64.toNativeUtf8(allocator: arena);
        final pk = keyB64.toNativeUtf8(allocator: arena);
        final outLenPtr = arena.allocate<IntPtr>(sizeOf<IntPtr>());

        final dataPtr = _ren_decrypt_file_raw(
          ctPtr,
          ciphertextBytes.length,
          pn,
          pk,
          outLenPtr,
        );

        if (dataPtr == nullptr) {
          return null;
        }

        final len = outLenPtr.value;
        final dataList = dataPtr.asTypedList(len);
        final bytesOut = Uint8List.fromList(dataList);
        ren_free_bytes(dataPtr, len);
        return bytesOut;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Оборачивает (шифрует) симметричный ключ для получателя с публичным ключом.
  /// Возвращает карту: `wrapped` (base64), `ephemeral_public_key` (base64), `nonce` (base64).
  Map<String, String>? wrapSymmetricKey(
    String keyB64,
    String receiverPublicKeyB64,
  ) {
    try {
      return using((arena) {
        final pKey = keyB64.toNativeUtf8(allocator: arena);
        final pRecv = receiverPublicKeyB64.toNativeUtf8(allocator: arena);
        final res = _ren_wrap_symmetric_key(pKey, pRecv);
        if (res.wrapped_key == nullptr) {
          return null;
        }
        final wrapped = _readAndFreeString(res.wrapped_key);
        final eph = _readAndFreeString(res.ephemeral_public_key);
        final nonce = _readAndFreeString(res.nonce);
        return {
          'wrapped': wrapped,
          'ephemeral_public_key': eph,
          'nonce': nonce,
        };
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Снимает обёртку с симметричного ключа.
  /// Параметры: `wrappedB64`, `ephemeralPublicKeyB64`, `nonceB64`, `receiverPrivateKeyB64` — все base64.
  /// Возвращает исходный симметричный ключ (base64) или null.
  String? unwrapSymmetricKey(
    String wrappedB64,
    String ephemeralPublicKeyB64,
    String nonceB64,
    String receiverPrivateKeyB64,
  ) {
    try {
      return using((arena) {
        final pw = wrappedB64.toNativeUtf8(allocator: arena);
        final peph = ephemeralPublicKeyB64.toNativeUtf8(allocator: arena);
        final pn = nonceB64.toNativeUtf8(allocator: arena);
        final pr = receiverPrivateKeyB64.toNativeUtf8(allocator: arena);
        final pres = _ren_unwrap_symmetric_key(pw, peph, pn, pr);
        if (pres == nullptr) {
          return null;
        }
        final k = pres.toDartString();
        ren_free_string(pres);
        return k;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Safe helper: читать строку из Pointer<Utf8> и освободить нативную память.
  String readAndFreeString(Pointer<Utf8> p) {
    try {
      if (p == nullptr) {
        return '';
      }
      final s = p.toDartString();
      ren_free_string(p);
      return s;
    } catch (e) {
      rethrow;
    }
  }

  /// Возвращает nonce как Dart String (вызывает нативную функцию и освобождает).
  String generateNonce() {
    try {
      final p = _ren_generate_nonce();
      final s = readAndFreeString(p);
      return s;
    } catch (e) {
      rethrow;
    }
  }

  /// Генерирует криптографическую соль (base64) на стороне нативного SDK.
  /// Возвращает строку base64 и сразу освобождает нативную память.
  String generateSalt() {
    try {
      final p = _ren_generate_salt();
      final s = readAndFreeString(p);
      return s;
    } catch (e) {
      rethrow;
    }
  }

  /// Генерирует пару ключей асимметричного шифрования.
  /// Возвращает Map с полями: 'public_key' и 'private_key' (обе строки base64).
  Map<String, String>? generateKeyPair() {
    try {
      final pair = _ren_generate_key_pair();
      if (pair.public_key == nullptr || pair.private_key == nullptr) {
        return null;
      }
      final pub = _readAndFreeString(pair.public_key);
      final priv = _readAndFreeString(pair.private_key);
      return {'public_key': pub, 'private_key': priv};
    } catch (e) {
      rethrow;
    }
  }

  /// Генерирует случайный симметричный ключ для сообщений (base64).
  String generateMessageKey() {
    try {
      final p = _ren_generate_message_key();
      final s = readAndFreeString(p);
      return s;
    } catch (e) {
      rethrow;
    }
  }

  /// KDF: Производит вывод симметричного ключа из пароля и соли (обе строки).
  /// Параметры: password и salt (строки), результат — base64-ключ.
  String deriveKeyFromPassword(String password, String salt) {
    try {
      return using((arena) {
        final pp = password.toNativeUtf8(allocator: arena);
        final ps = salt.toNativeUtf8(allocator: arena);
        final pOut = _ren_derive_key_from_password(pp, ps);
        final out = readAndFreeString(pOut);
        return out;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// KDF: Производит вывод симметричного ключа из произвольной строки.
  /// Параметр: input (строка), результат — base64-ключ.
  String deriveKeyFromString(String input) {
    try {
      return using((arena) {
        final pi = input.toNativeUtf8(allocator: arena);
        final pOut = _ren_derive_key_from_string(pi);
        final out = readAndFreeString(pOut);
        return out;
      });
    } catch (e) {
      rethrow;
    }
  }

  // ==============================
  // P0-4: X3DH & Double Ratchet Methods
  // ==============================

  /// X3DH Initiate (Alice)
  /// Returns Base64-encoded shared secret
  String? x3dhInitiate({
    required String identitySecretKey,
    required String ephemeralPublicKey,
    required String ephemeralSecretKey,
    required String theirIdentityKey,
    required String theirSignedPreKey,
    String? theirOneTimePreKey,
  }) {
    try {
      return using((arena) {
        final pIdentitySk = identitySecretKey.toNativeUtf8(allocator: arena);
        final pEphPk = ephemeralPublicKey.toNativeUtf8(allocator: arena);
        final pEphSk = ephemeralSecretKey.toNativeUtf8(allocator: arena);
        final pTheirIk = theirIdentityKey.toNativeUtf8(allocator: arena);
        final pTheirSpk = theirSignedPreKey.toNativeUtf8(allocator: arena);
        final pTheirOtk = theirOneTimePreKey?.toNativeUtf8(allocator: arena) ??
            nullptr;

        final result = _x3dh_initiate(
          pIdentitySk,
          pEphPk,
          pEphSk,
          pTheirIk,
          pTheirSpk,
          pTheirOtk,
        );

        if (result == nullptr) return null;

        final secret = result.toDartString();
        ren_free_string(result);
        return secret;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// X3DH Respond (Bob)
  /// Returns Base64-encoded shared secret
  String? x3dhRespond({
    required String identitySecretKey,
    required String signedPreKeySecret,
    required String theirIdentityKey,
    required String theirEphemeralKey,
    String? oneTimePreKeySecret,
  }) {
    try {
      return using((arena) {
        final pIdentitySk = identitySecretKey.toNativeUtf8(allocator: arena);
        final pSpkSk = signedPreKeySecret.toNativeUtf8(allocator: arena);
        final pTheirIk = theirIdentityKey.toNativeUtf8(allocator: arena);
        final pTheirEph = theirEphemeralKey.toNativeUtf8(allocator: arena);
        final pOtkSk =
            oneTimePreKeySecret?.toNativeUtf8(allocator: arena) ?? nullptr;

        final result = _x3dh_respond(
          pIdentitySk,
          pSpkSk,
          pTheirIk,
          pTheirEph,
          pOtkSk,
        );

        if (result == nullptr) return null;

        final secret = result.toDartString();
        ren_free_string(result);
        return secret;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Ratchet Session Initiate (Alice)
  /// Returns JSON-serialized session state
  String? ratchetInitiate({
    required String sharedSecretB64,
    required String localIdentityPublic,
    required String remoteIdentityPublic,
  }) {
    try {
      return using((arena) {
        final pSecret = sharedSecretB64.toNativeUtf8(allocator: arena);
        final pLocalId = localIdentityPublic.toNativeUtf8(allocator: arena);
        final pRemoteId = remoteIdentityPublic.toNativeUtf8(allocator: arena);

        final result = _ratchet_initiate(pSecret, pLocalId, pRemoteId);

        if (result == nullptr) return null;

        final state = result.toDartString();
        ren_free_string(result);
        return state;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Ratchet Session Respond (Bob)
  /// Returns JSON-serialized session state
  String? ratchetRespond({
    required String sharedSecretB64,
    required String localIdentityPublic,
    required String remoteIdentityPublic,
    required String remoteRatchetKey,
  }) {
    try {
      return using((arena) {
        final pSecret = sharedSecretB64.toNativeUtf8(allocator: arena);
        final pLocalId = localIdentityPublic.toNativeUtf8(allocator: arena);
        final pRemoteId = remoteIdentityPublic.toNativeUtf8(allocator: arena);
        final pRemoteRatchet =
            remoteRatchetKey.toNativeUtf8(allocator: arena);

        final result = _ratchet_respond(
          pSecret,
          pLocalId,
          pRemoteId,
          pRemoteRatchet,
        );

        if (result == nullptr) return null;

        final state = result.toDartString();
        ren_free_string(result);
        return state;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Ratchet Encrypt
  /// Returns JSON with session_state and message
  String? ratchetEncrypt({
    required String sessionStateJson,
    required String plaintext,
  }) {
    try {
      return using((arena) {
        final pSession = sessionStateJson.toNativeUtf8(allocator: arena);
        final pPlaintext = plaintext.toNativeUtf8(allocator: arena);

        final result = _ratchet_encrypt(pSession, pPlaintext);

        if (result == nullptr) return null;

        final output = result.toDartString();
        ren_free_string(result);
        return output;
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Ratchet Decrypt
  /// Returns JSON with session_state and plaintext (Base64)
  String? ratchetDecrypt({
    required String sessionStateJson,
    required Map<String, dynamic> message,
  }) {
    try {
      return using((arena) {
        final pSession = sessionStateJson.toNativeUtf8(allocator: arena);
        final messageJson = jsonEncode(message);
        final pMessage = messageJson.toNativeUtf8(allocator: arena);

        final result = _ratchet_decrypt(pSession, pMessage);

        if (result == nullptr) return null;

        final output = result.toDartString();
        ren_free_string(result);
        return output;
      });
    } catch (e) {
      rethrow;
    }
  }
}
