import 'dart:io';

import 'package:dio/dio.dart';

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
    final token = await SecureStorage.readKey(Keys.Token);
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
    try {
      final form = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(
          file.path,
          filename: file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : 'avatar.jpg',
        ),
      });
      final resp = await dio.post(
        '${Apiurl.api}/users/avatar',
        data: form,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
      return (resp.data as Map<String, dynamic>?) ?? <String, dynamic>{};
    } on DioException catch (e) {
      throw ApiException(
        (e.response?.data is String)
            ? e.response?.data as String
            : 'Ошибка загрузки аватара',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> removeAvatar() async {
    final token = await _requireToken();
    try {
      final form = FormData.fromMap({'remove': 'true'});
      final resp = await dio.post(
        '${Apiurl.api}/users/avatar',
        data: form,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
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
}
