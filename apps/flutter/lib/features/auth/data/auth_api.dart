import 'package:dio/dio.dart';

import 'package:ren/core/constants/api_url.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class AuthApi {
  final Dio dio;

  AuthApi(this.dio);

  Future<Map<String, dynamic>> login(
    String login,
    String password,
    bool rememberMe,
  ) async {
    try {
      final response = await dio.post(
        '${Apiurl.api}/auth/login',
        data: {'login': login, 'password': password, 'remember_me': rememberMe},
      );

      return response.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      switch (status) {

        case 401:
          throw ApiException(
            'Неверный логин или пароль.',
          );
        case 500:
          throw ApiException('Ошибка сервера. Попробуйте позже.');
        default:
          // Сообщение из тела ответа, если есть
          final serverMessage = (e.response?.data is Map<String, dynamic>)
              ? (e.response?.data['message'] as String?)
              : null;
          throw ApiException(
            serverMessage ??
                'Неизвестная ошибка${status != null ? ' ($status)' : ''}.',
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
  ) async {
    try {
      final response = await dio.post(
        '${Apiurl.api}/auth/register',
        data: {
          'login': login,
          'password': password,
          'username': username,
          'pkebymk': pkebymk,
          'pkebyrk': pkebyrk,
          'pubk': pubk,
          'salt': salt,
        },
      );
      return response.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      switch (status) {
        case 400:
          throw ApiException(
            'Некорректные данные. Проверьте обязательные поля и требования к паролю.',
          );
        case 409:
          throw ApiException(
            'Логин или имя пользователя занято. Выберите другой логин/ник.',
          );
        case 500:
          throw ApiException('Ошибка сервера. Попробуйте позже.');
        default:
          // Сообщение из тела ответа, если есть
          final serverMessage = (e.response?.data is Map<String, dynamic>)
              ? (e.response?.data['message'] as String?)
              : null;
          throw ApiException(
            serverMessage ??
                'Неизвестная ошибка${status != null ? ' ($status)' : ''}.',
          );
      }
    } catch (_) {
      throw ApiException(
        'Не удалось подключиться к серверу. Проверьте соединение.',
      );
    }
  }

  Future<void> recovery() async {}
}
