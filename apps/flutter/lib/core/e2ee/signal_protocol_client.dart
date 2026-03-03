import 'dart:async';

class IdentityChangeEvent {
  final int peerUserId;
  final String? previousFingerprint;
  final String? currentFingerprint;

  const IdentityChangeEvent({
    required this.peerUserId,
    this.previousFingerprint,
    this.currentFingerprint,
  });
}

class SignalProtocolClient {
  SignalProtocolClient._();

  static final SignalProtocolClient instance = SignalProtocolClient._();

  final StreamController<IdentityChangeEvent> _identityChangesController =
      StreamController<IdentityChangeEvent>.broadcast();

  Stream<IdentityChangeEvent> get identityChanges =>
      _identityChangesController.stream;

  Future<void> initialize() async {}

  Future<Map<String, dynamic>> initUser({
    required int userId,
    int deviceId = 1,
  }) async {
    return const <String, dynamic>{};
  }

  Future<bool> hasSession({required int peerUserId, int deviceId = 1}) async {
    return false;
  }

  Future<String> encrypt({
    required int peerUserId,
    required String plaintext,
    int deviceId = 1,
    Map<String, dynamic>? preKeyBundle,
  }) async {
    throw UnsupportedError('Signal runtime is disabled');
  }

  Future<String> decrypt({
    required int peerUserId,
    required String ciphertext,
    int deviceId = 1,
  }) async {
    throw UnsupportedError('Signal runtime is disabled');
  }

  Future<void> resetSession({
    required int peerUserId,
    int deviceId = 1,
  }) async {}

  Future<String> getFingerprint({
    required int peerUserId,
    int deviceId = 1,
  }) async {
    throw UnsupportedError('Signal runtime is disabled');
  }

  Future<String> exportBackup({
    required int userId,
    int deviceId = 1,
    required String backupSecretBase64,
  }) async {
    throw UnsupportedError('Signal runtime is disabled');
  }

  Future<bool> importBackup({
    required int userId,
    int deviceId = 1,
    required String backupSecretBase64,
    required String encryptedPayload,
  }) async {
    return false;
  }
}
