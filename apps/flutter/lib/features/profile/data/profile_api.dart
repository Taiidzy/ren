import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/secure/secure_storage.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class ProfileApi {
  final Dio dio;

  ProfileApi(this.dio);

  Future<String> _requireToken() async {
    final token = await SecureStorage.readKey(Keys.token);
    if (token == null || token.isEmpty) {
      throw ApiException('Нет токена авторизации');
    }
    return token;
  }

  Future<Map<String, dynamic>> me() async {
    final token = await _requireToken();
    try {
      final resp = await dio.get(
        '${Apiurl.api}/users/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as Map<String, dynamic>?) ?? <String, dynamic>{};
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка загрузки профиля',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> updateUsername(String username) async {
    final token = await _requireToken();
    try {
      final resp = await dio.patch(
        '${Apiurl.api}/users/username',
        data: {'username': username},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as Map<String, dynamic>?) ?? <String, dynamic>{};
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка обновления имени',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> uploadAvatar(File file) async {
    final token = await _requireToken();

    final uri = Uri.parse('${Apiurl.api}/users/avatar');
    final request = http.MultipartRequest('POST', uri);

    // ❗ ТОЛЬКО Authorization
    request.headers['Authorization'] = 'Bearer $token';

    final filename = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'avatar.jpg';

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
      if (response.body.isEmpty) return {};
      return json.decode(response.body) as Map<String, dynamic>;
    }

    throw ApiException(
      response.body.isNotEmpty ? response.body : 'Ошибка загрузки аватара',
      statusCode: response.statusCode,
    );
  }

  Future<Map<String, dynamic>> removeAvatar() async {
    final token = await _requireToken();
    try {
      final form = FormData.fromMap({'remove': 'true'});
      final resp = await dio.post(
        '${Apiurl.api}/users/avatar',
        data: form,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as Map<String, dynamic>?) ?? <String, dynamic>{};
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка удаления аватара',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<List<dynamic>> sessions() async {
    final token = await _requireToken();
    try {
      final resp = await dio.get(
        '${Apiurl.api}/auth/sessions',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (resp.data as List<dynamic>?) ?? const [];
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка загрузки сессий',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> deleteSession(String sessionId) async {
    final token = await _requireToken();
    try {
      await dio.delete(
        '${Apiurl.api}/auth/sessions/$sessionId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка удаления сессии',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> deleteOtherSessions() async {
    final token = await _requireToken();
    try {
      await dio.delete(
        '${Apiurl.api}/auth/sessions',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка завершения других сессий',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
