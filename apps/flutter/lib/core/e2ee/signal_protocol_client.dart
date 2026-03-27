import 'dart:async';

import 'package:flutter/services.dart';

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

  static const MethodChannel _channel = MethodChannel('ren/signal_protocol');
  static const EventChannel _events = EventChannel('ren/signal_protocol/events');

  final StreamController<IdentityChangeEvent> _identityChangesController =
      StreamController<IdentityChangeEvent>.broadcast();
  StreamSubscription<dynamic>? _eventSub;
  bool _initialized = false;

  Stream<IdentityChangeEvent> get identityChanges =>
      _identityChangesController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _eventSub = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final data = event.cast<String, dynamic>();
        final type = (data['type'] as String?)?.trim();
        if (type != 'identity_changed') return;
        final peerId = (data['peer_user_id'] is int)
            ? data['peer_user_id'] as int
            : int.tryParse('${data['peer_user_id'] ?? ''}') ?? 0;
        if (peerId <= 0) return;
        _identityChangesController.add(
          IdentityChangeEvent(
            peerUserId: peerId,
            previousFingerprint: data['previous_fingerprint'] as String?,
            currentFingerprint: data['current_fingerprint'] as String?,
          ),
        );
      },
      onError: (_) {},
    );
  }

  Future<Map<String, dynamic>> initUser({
    required int userId,
    int deviceId = 1,
  }) async {
    await initialize();
    final raw = await _channel.invokeMethod<dynamic>('initUser', {
      'userId': userId,
      'deviceId': deviceId,
    });
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  Future<bool> hasSession({required int peerUserId, int deviceId = 1}) async {
    await initialize();
    final raw = await _channel.invokeMethod<dynamic>('hasSession', {
      'peerUserId': peerUserId,
      'deviceId': deviceId,
    });
    return raw == true;
  }

  Future<String> encrypt({
    required int peerUserId,
    required String plaintext,
    int deviceId = 1,
    Map<String, dynamic>? preKeyBundle,
  }) async {
    await initialize();
    final raw = await _channel.invokeMethod<dynamic>('encrypt', {
      'peerUserId': peerUserId,
      'deviceId': deviceId,
      'plaintext': plaintext,
      if (preKeyBundle != null) 'preKeyBundle': preKeyBundle,
    });
    return (raw as String?) ?? '';
  }

  Future<String> decrypt({
    required int peerUserId,
    required String ciphertext,
    int deviceId = 1,
  }) async {
    await initialize();
    final raw = await _channel.invokeMethod<dynamic>('decrypt', {
      'peerUserId': peerUserId,
      'deviceId': deviceId,
      'ciphertext': ciphertext,
    });
    return (raw as String?) ?? '';
  }

  Future<void> resetSession({
    required int peerUserId,
    int deviceId = 1,
  }) async {
    await initialize();
    await _channel.invokeMethod<dynamic>('resetSession', {
      'peerUserId': peerUserId,
      'deviceId': deviceId,
    });
  }

  Future<String> getFingerprint({
    required int peerUserId,
    int deviceId = 1,
  }) async {
    await initialize();
    final raw = await _channel.invokeMethod<dynamic>('getFingerprint', {
      'peerUserId': peerUserId,
      'deviceId': deviceId,
    });
    return (raw as String?) ?? '';
  }

  Future<String> exportBackup({
    required int userId,
    int deviceId = 1,
    required String backupSecretBase64,
  }) async {
    await initialize();
    final raw = await _channel.invokeMethod<dynamic>('exportBackup', {
      'userId': userId,
      'deviceId': deviceId,
      'backupSecretBase64': backupSecretBase64,
    });
    return (raw as String?) ?? '';
  }

  Future<bool> importBackup({
    required int userId,
    int deviceId = 1,
    required String backupSecretBase64,
    required String encryptedPayload,
  }) async {
    await initialize();
    final raw = await _channel.invokeMethod<dynamic>('importBackup', {
      'userId': userId,
      'deviceId': deviceId,
      'backupSecretBase64': backupSecretBase64,
      'encryptedPayload': encryptedPayload,
    });
    return raw == true;
  }
}
