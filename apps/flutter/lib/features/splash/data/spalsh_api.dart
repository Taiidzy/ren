import 'package:dio/dio.dart';

import 'package:ren/core/constants/api_url.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class SplashApi {
  final Dio dio;

  SplashApi(this.dio);

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

  Future<Map<String, dynamic>> verefyToken(String token) async {
    try {
      final response = await dio.get(
        '${Apiurl.api}/users/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
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
          throw ApiException('Токен недействителен.', statusCode: 401);
        case 500:
          throw ApiException(
            'Ошибка сервера. Попробуйте позже.',
            statusCode: 500,
          );
        default:
          final serverMessage = _extractServerMessage(e.response?.data);
          throw ApiException(
            serverMessage ??
                'Ошибка валидации токена${status != null ? ' ($status)' : ''}.',
            statusCode: status,
          );
      }
    } catch (_) {
      throw ApiException(
        'Не удалось подключиться к серверу. Проверьте соединение.',
      );
    }
  }
}
