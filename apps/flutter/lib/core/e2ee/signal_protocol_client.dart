import 'dart:async';

import 'package:flutter/foundation.dart';
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
  static const EventChannel _events = EventChannel(
    'ren/signal_protocol/events',
  );

  final StreamController<IdentityChangeEvent> _identityChangesController =
      StreamController<IdentityChangeEvent>.broadcast();

  Stream<IdentityChangeEvent> get identityChanges =>
      _identityChangesController.stream;

  bool _eventsSubscribed = false;

  Future<void> initialize() async {
    if (_eventsSubscribed) return;
    _eventsSubscribed = true;

    _events.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (raw is! Map) return;
        final map = Map<String, dynamic>.from(raw);
        if ((map['type'] as String?) != 'identity_changed') return;
        final peer = (map['peer_user_id'] is int)
            ? map['peer_user_id'] as int
            : int.tryParse('${map['peer_user_id'] ?? ''}') ?? 0;
        if (peer <= 0) return;
        _identityChangesController.add(
          IdentityChangeEvent(
            peerUserId: peer,
            previousFingerprint: map['previous_fingerprint'] as String?,
            currentFingerprint: map['current_fingerprint'] as String?,
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('signal events error: $error');
      },
    );
  }

  Future<Map<String, dynamic>> initUser({
    required int userId,
    int deviceId = 1,
  }) async {
    final res = await _channel.invokeMethod<Map>('initUser', {
      'userId': userId,
      'deviceId': deviceId,
    });
    return (res ?? const {}).cast<String, dynamic>();
  }

  Future<bool> hasSession({required int peerUserId, int deviceId = 1}) async {
    final has = await _channel.invokeMethod<bool>('hasSession', {
      'peerUserId': peerUserId,
      'deviceId': deviceId,
    });
    return has ?? false;
  }

  Future<String> encrypt({
    required int peerUserId,
    required String plaintext,
    int deviceId = 1,
    Map<String, dynamic>? preKeyBundle,
  }) async {
    final res = await _channel.invokeMethod<String>('encrypt', {
      'peerUserId': peerUserId,
      'deviceId': deviceId,
      'plaintext': plaintext,
      if (preKeyBundle != null) 'preKeyBundle': preKeyBundle,
    });
    if (res == null || res.isEmpty) {
      throw StateError('Signal encrypt returned empty ciphertext');
    }
    return res;
  }

  Future<String> decrypt({
    required int peerUserId,
    required String ciphertext,
    int deviceId = 1,
  }) async {
    final res = await _channel.invokeMethod<String>('decrypt', {
      'peerUserId': peerUserId,
      'deviceId': deviceId,
      'ciphertext': ciphertext,
    });
    if (res == null) {
      throw StateError('Signal decrypt returned null');
    }
    return res;
  }

  Future<void> resetSession({required int peerUserId, int deviceId = 1}) async {
    await _channel.invokeMethod<void>('resetSession', {
      'peerUserId': peerUserId,
      'deviceId': deviceId,
    });
  }

  Future<String> getFingerprint({
    required int peerUserId,
    int deviceId = 1,
  }) async {
    final fp = await _channel.invokeMethod<String>('getFingerprint', {
      'peerUserId': peerUserId,
      'deviceId': deviceId,
    });
    if (fp == null || fp.isEmpty) {
      throw StateError('Signal fingerprint is empty');
    }
    return fp;
  }
}
