/// PreKey Repository
/// 
/// Управление PreKeys: загрузка на сервер, получение bundle других пользователей

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'x3dh_protocol.dart';

/// One-Time PreKey для загрузки
class OneTimePreKey {
  final int prekeyId;
  final String prekey;

  OneTimePreKey({
    required this.prekeyId,
    required this.prekey,
  });

  Map<String, dynamic> toJson() => {
    'prekey_id': prekeyId,
    'prekey': prekey,
  };
}

/// PreKey Repository
class PreKeyRepository {
  final http.Client _client;
  final String baseUrl;

  PreKeyRepository({
    http.Client? client,
    this.baseUrl = 'http://localhost:8080',
  }) : _client = client ?? http.Client();

  /// Получить PreKey Bundle пользователя
  Future<PreKeyBundle> getBundle(int userId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/keys/$userId/bundle'),
    );

    if (response.statusCode == 404) {
      throw Exception('User not found or has no prekeys');
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to get prekey bundle: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return PreKeyBundle.fromJson(json);
  }

  /// Загрузить One-Time PreKeys на сервер
  Future<void> uploadOneTimePreKeys(List<OneTimePreKey> prekeys) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/keys/one-time'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'prekeys': prekeys.map((k) => k.toJson()).toList(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to upload prekeys: ${response.statusCode}');
    }
  }

  /// Загрузить Signed PreKey на сервер
  Future<void> uploadSignedPreKey(String prekey, String signature) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/keys/signed'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'prekey': prekey,
        'signature': signature,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to upload signed prekey: ${response.statusCode}');
    }
  }

  /// Пометить One-Time PreKey как использованный
  Future<void> consumePreKey(int preKeyId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/keys/one-time/$preKeyId'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to consume prekey: ${response.statusCode}');
    }
  }

  /// Проверить и пополнить запас One-Time PreKeys
  /// Если на сервере меньше чем minCount, загружаем новые
  Future<void> syncPreKeys({
    required int userId,
    required Future<List<OneTimePreKey>> Function() generatePreKeys,
    int minCount = 50,
    int maxCount = 100,
  }) async {
    // Пока заглушка - нужна реализация подсчёта OTPK на сервере
    // В реальности нужно добавить endpoint GET /keys/one-time/count
    return;
  }

  /// Освободить ресурсы
  void dispose() {
    _client.close();
  }
}
