import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/sdk/ren_sdk.dart';
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
    final token = await SecureStorage.readKey(Keys.token);
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

  Future<List<dynamic>> searchUsers(String query, {int limit = 15}) async {
    final token = await _requireToken();
    try {
      final resp = await dio.get(
        '${Apiurl.api}/users/search',
        queryParameters: {'q': query, 'limit': limit},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as List<dynamic>?) ?? const [];
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка поиска пользователей',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> addFavorite(int chatId) async {
    final token = await _requireToken();
    try {
      await dio.post(
        '${Apiurl.api}/chats/$chatId/favorite',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка добавления в избранное',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> removeFavorite(int chatId) async {
    final token = await _requireToken();
    try {
      await dio.delete(
        '${Apiurl.api}/chats/$chatId/favorite',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка удаления из избранного',
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
        data: {'kind': kind, 'title': title, 'user_ids': userIds},
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

  Future<Map<String, dynamic>> markChatRead(
    int chatId, {
    int? messageId,
  }) async {
    final token = await _requireToken();
    try {
      final resp = await dio.post(
        '${Apiurl.api}/chats/$chatId/read',
        data: {if (messageId != null && messageId > 0) 'message_id': messageId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as Map<String, dynamic>?) ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка отметки прочтения',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> markChatDelivered(
    int chatId, {
    int? messageId,
  }) async {
    final token = await _requireToken();
    try {
      final resp = await dio.post(
        '${Apiurl.api}/chats/$chatId/delivered',
        data: {if (messageId != null && messageId > 0) 'message_id': messageId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as Map<String, dynamic>?) ?? const <String, dynamic>{};
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка отметки доставки',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<List<dynamic>> listMembers(int chatId) async {
    final token = await _requireToken();
    try {
      final resp = await dio.get(
        '${Apiurl.api}/chats/$chatId/members',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as List<dynamic>?) ?? const [];
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка загрузки участников',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> addMember(
    int chatId, {
    required int userId,
    String? role,
  }) async {
    final token = await _requireToken();
    try {
      await dio.post(
        '${Apiurl.api}/chats/$chatId/members',
        data: {
          'user_id': userId,
          if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка добавления участника',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> updateMemberRole(
    int chatId, {
    required int userId,
    required String role,
  }) async {
    final token = await _requireToken();
    try {
      await dio.patch(
        '${Apiurl.api}/chats/$chatId/members/$userId',
        data: {'role': role},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка изменения роли участника',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> removeMember(int chatId, {required int userId}) async {
    final token = await _requireToken();
    try {
      await dio.delete(
        '${Apiurl.api}/chats/$chatId/members/$userId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка удаления участника',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> updateChatInfo(
    int chatId, {
    String? title,
    String? avatarPath,
  }) async {
    final token = await _requireToken();
    try {
      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      if (avatarPath != null) data['avatar'] = avatarPath;

      await dio.patch(
        '${Apiurl.api}/chats/$chatId',
        data: data,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка обновления информации о чате',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> uploadChatAvatar(int chatId, File file) async {
    final token = await _requireToken();
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        final uri = Uri.parse('${Apiurl.api}/chats/$chatId/avatar');
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer $token';
        final sdkFingerprint = currentSdkFingerprint();
        if (sdkFingerprint.isNotEmpty) {
          request.headers['X-SDK-Fingerprint'] = sdkFingerprint;
        }

        final filename = file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : 'chat_avatar.jpg';
        request.files.add(
          await http.MultipartFile.fromPath(
            'avatar',
            file.path,
            filename: filename,
          ),
        );

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return;
        }
        throw ApiException(
          response.body.isNotEmpty
              ? response.body
              : 'Ошибка загрузки аватара чата',
          statusCode: response.statusCode,
        );
      } on SocketException {
        await Future<void>.delayed(_delayForAttempt(attempt));
      } on HttpException {
        await Future<void>.delayed(_delayForAttempt(attempt));
      } on TimeoutException {
        await Future<void>.delayed(_delayForAttempt(attempt));
      }
    }
  }

  Future<void> removeChatAvatar(int chatId) async {
    final token = await _requireToken();
    try {
      final form = FormData.fromMap({'remove': 'true'});
      await dio.post(
        '${Apiurl.api}/chats/$chatId/avatar',
        data: form,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка удаления аватара чата',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Duration _delayForAttempt(int attempt) {
    if (attempt <= 1) return const Duration(milliseconds: 200);
    if (attempt == 2) return const Duration(milliseconds: 500);
    if (attempt == 3) return const Duration(seconds: 1);
    return const Duration(seconds: 2);
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
        'file': MultipartFile.fromBytes(ciphertextBytes, filename: filename),
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
