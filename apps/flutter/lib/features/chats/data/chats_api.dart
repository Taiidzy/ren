import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/core/constants/keys.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class ChatsApi {
  final Dio dio;

  ChatsApi(this.dio);

  Future<String> _requireToken() async {
    final token = await SecureStorage.readKey(Keys.Token);
    if (token == null || token.isEmpty) {
      throw ApiException('Нет токена авторизации');
    }
    return token;
  }

  Future<List<dynamic>> listChats() async {
    final token = await _requireToken();
    try {
      final resp = await dio.get(
        '${Apiurl.api}/chats',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as List<dynamic>?) ?? const [];
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка загрузки чатов',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<List<dynamic>> getMessages(
    int chatId, {
    int? limit,
    int? beforeId,
    int? afterId,
  }) async {
    final token = await _requireToken();
    try {
      final resp = await dio.get(
        '${Apiurl.api}/chats/$chatId/messages',
        queryParameters: {
          if (limit != null) 'limit': limit,
          if (beforeId != null) 'before_id': beforeId,
          if (afterId != null) 'after_id': afterId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as List<dynamic>?) ?? const [];
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка загрузки сообщений',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> createChat({
    required String kind,
    String? title,
    required List<int> userIds,
  }) async {
    final token = await _requireToken();
    try {
      final resp = await dio.post(
        '${Apiurl.api}/chats',
        data: {
          'kind': kind,
          'title': title,
          'user_ids': userIds,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as Map<String, dynamic>?) ?? <String, dynamic>{};
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка создания чата',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> deleteChat(int chatId, {bool forAll = false}) async {
    final token = await _requireToken();
    try {
      await dio.delete(
        '${Apiurl.api}/chats/$chatId',
        queryParameters: {'for_all': forAll},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка удаления чата',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<String> getPublicKey(int userId) async {
    try {
      final token = await _requireToken();
      final resp = await dio.get(
        '${Apiurl.api}/users/$userId/public-key',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = (resp.data as Map<String, dynamic>?);
      final pk = data?['public_key'] as String?;
      if (pk == null || pk.isEmpty) {
        throw ApiException('Публичный ключ не найден');
      }
      return pk;
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка получения публичного ключа',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> uploadMedia({
    required int chatId,
    required List<int> ciphertextBytes,
    required String filename,
    required String mimetype,
  }) async {
    final token = await _requireToken();
    try {
      final form = FormData.fromMap({
        'chat_id': chatId,
        'filename': filename,
        'mimetype': mimetype,
        'file': MultipartFile.fromBytes(
          ciphertextBytes,
          filename: filename,
        ),
      });

      final resp = await dio.post(
        '${Apiurl.api}/media',
        data: form,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as Map<String, dynamic>?) ?? <String, dynamic>{};
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка загрузки файла',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<Uint8List> downloadMedia(int fileId) async {
    final token = await _requireToken();
    try {
      final resp = await dio.get<List<int>>(
        '${Apiurl.api}/media/$fileId',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.bytes,
        ),
      );
      final data = resp.data ?? <int>[];
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка скачивания файла',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
