import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/sdk/ren_sdk.dart';
import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/core/constants/keys.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class AuthApi {
  final Dio dio;

  AuthApi(this.dio);

  String? _extractServerMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final value = data['message'] ?? data['error'] ?? data['detail'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    } else if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }
    return null;
  }

  Map<String, dynamic> _publicAuthHeaders() {
    final sdkFingerprint = currentSdkFingerprint();
    if (sdkFingerprint.isEmpty) return const <String, dynamic>{};
    return <String, dynamic>{'X-SDK-Fingerprint': sdkFingerprint};
  }

  Future<Map<String, dynamic>> login(
    String login,
    String password,
    bool rememberMe,
  ) async {
    try {
      final response = await dio.post(
        '${Apiurl.api}/auth/login',
        data: {'login': login, 'password': password, 'remember_me': rememberMe},
        options: Options(headers: _publicAuthHeaders()),
      );

      return response.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (e.response == null) {
        throw ApiException(
          'Сетевая ошибка (${e.type.name}). Проверьте интернет/VPN и доступ к API.',
        );
      }
      switch (status) {
        case 401:
          final serverMessage = _extractServerMessage(e.response?.data) ?? '';
          if (serverMessage.toLowerCase().contains('sdk fingerprint')) {
            throw ApiException(
              'Сервер требует SDK fingerprint, но клиент его не передал. Проверьте сборку Ren-SDK и заголовок X-SDK-Fingerprint.',
            );
          }
          throw ApiException('Неверный логин или пароль.');
        case 500:
          throw ApiException('Ошибка сервера. Попробуйте позже.');
        case 502:
        case 503:
        case 504:
          throw ApiException('Сервер временно недоступен. Попробуйте позже.');
        default:
          final serverMessage = _extractServerMessage(e.response?.data);
          if (kDebugMode) {
            debugPrint(
              'AuthApi.login failed (status=$status, type=${e.type}, message=${e.message}, data=${e.response?.data})',
            );
          }
          throw ApiException(
            serverMessage ??
                'Ошибка авторизации${status != null ? ' ($status)' : ''}.',
          );
      }
    } catch (_) {
      throw ApiException(
        'Не удалось подключиться к серверу. Проверьте соединение.',
      );
    }
  }

  Future<Map<String, dynamic>> register(
    String login,
    String password,
    String username,
    String pkebymk,
    String pkebyrk,
    String pubk,
    String salt,
    String? nickname,
  ) async {
    try {
      final response = await dio.post(
        '${Apiurl.api}/auth/register',
        data: {
          'login': login,
          'password': password,
          'username': username,
          'nickname': nickname,
          'pkebymk': pkebymk,
          'pkebyrk': pkebyrk,
          'pubk': pubk,
          'salt': salt,
        },
        options: Options(headers: _publicAuthHeaders()),
      );
      return response.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (e.response == null) {
        throw ApiException(
          'Сетевая ошибка (${e.type.name}). Проверьте интернет/VPN и доступ к API.',
        );
      }
      switch (status) {
        case 400:
          throw ApiException(
            'Некорректные данные. Проверьте обязательные поля и требования к паролю.',
          );
        case 422:
          throw ApiException(
            _extractServerMessage(e.response?.data) ??
                'Данные не прошли валидацию (422).',
          );
        case 409:
          throw ApiException(
            'Логин или имя пользователя занято. Выберите другой логин/ник.',
          );
        case 500:
          throw ApiException('Ошибка сервера. Попробуйте позже.');
        case 502:
        case 503:
        case 504:
          throw ApiException('Сервер временно недоступен. Попробуйте позже.');
        default:
          final serverMessage = _extractServerMessage(e.response?.data);
          throw ApiException(
            serverMessage ??
                'Ошибка регистрации${status != null ? ' ($status)' : ''}.',
          );
      }
    } catch (_) {
      throw ApiException(
        'Не удалось подключиться к серверу. Проверьте соединение.',
      );
    }
  }

  Future<List<dynamic>> searchUsers(String query, {int limit = 10}) async {
    try {
      final token = await SecureStorage.readKey(Keys.token);
      if (token == null || token.isEmpty) {
        return const [];
      }
      final response = await dio.get(
        '${Apiurl.api}/users/search',
        queryParameters: {'q': query, 'limit': limit},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (response.data as List<dynamic>?) ?? const [];
    } on DioException catch (_) {
      return const [];
    }
  }

  Future<void> recovery() async {}

  Future<Map<String, dynamic>> updateNickname(String nickname) async {
    try {
      final response = await dio.patch(
        '${Apiurl.api}/users/nickname',
        data: {'nickname': nickname},
      );
      return response.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (e.response == null) {
        throw ApiException(
          'Сетевая ошибка (${e.type.name}). Проверьте интернет/VPN и доступ к API.',
        );
      }
      switch (status) {
        case 400:
          throw ApiException(
            _extractServerMessage(e.response?.data) ??
                'Некорректные данные (400).',
          );
        case 500:
          throw ApiException('Ошибка сервера. Попробуйте позже.');
        default:
          final serverMessage = _extractServerMessage(e.response?.data);
          throw ApiException(
            serverMessage ??
                'Ошибка обновления nickname${status != null ? ' ($status)' : ''}.',
          );
      }
    } catch (_) {
      throw ApiException(
        'Не удалось подключиться к серверу. Проверьте соединение.',
      );
    }
  }
}
