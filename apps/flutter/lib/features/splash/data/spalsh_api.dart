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

  Future<Map<String, dynamic>> verefyToken(String token) async {
    try {
      final response = await dio.get(
        '${Apiurl.api}/users/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      return response.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;

      switch (status) {
        case 401:
          throw ApiException('Токен недействителен.', statusCode: 401);
        case 500:
          throw ApiException(
            'Ошибка сервера. Попробуйте позже.',
            statusCode: 500,
          );
        default:
          // Сообщение из тела ответа, если есть
          final serverMessage = (e.response?.data is Map<String, dynamic>)
              ? (e.response?.data['message'] as String?)
              : null;
          throw ApiException(
            serverMessage ??
                'Неизвестная ошибка${status != null ? ' ($status)' : ''}.',
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
