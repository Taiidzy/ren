import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ren/features/auth/data/auth_api.dart';

typedef _RequestHandler =
    FutureOr<void> Function(
      RequestOptions options,
      RequestInterceptorHandler handler,
    );

Dio _dioWithRequestHandler(_RequestHandler onRequest) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        await onRequest(options, handler);
      },
    ),
  );
  return dio;
}

void main() {
  group('AuthApi.login', () {
    test('returns parsed payload for successful response', () async {
      Map<String, dynamic>? sentData;

      final dio = _dioWithRequestHandler((options, handler) {
        sentData = Map<String, dynamic>.from(options.data as Map);
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: <String, dynamic>{'token': 't', 'user': <String, dynamic>{}},
          ),
        );
      });

      final api = AuthApi(dio);
      final result = await api.login('alice', 'secret', true);

      expect(result['token'], 't');
      expect(sentData?['login'], 'alice');
      expect(sentData?['password'], 'secret');
      expect(sentData?['remember_me'], true);
    });

    test('maps 401 to user-friendly message', () async {
      final dio = _dioWithRequestHandler((options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 401,
              data: <String, dynamic>{'message': 'bad credentials'},
            ),
            type: DioExceptionType.badResponse,
          ),
        );
      });

      final api = AuthApi(dio);

      expect(
        () => api.login('alice', 'wrong', false),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Неверный логин или пароль.',
          ),
        ),
      );
    });

    test('uses backend message for unknown status', () async {
      final dio = _dioWithRequestHandler((options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 418,
              data: <String, dynamic>{'message': 'teapot'},
            ),
            type: DioExceptionType.badResponse,
          ),
        );
      });

      final api = AuthApi(dio);

      expect(
        () => api.login('alice', 'secret', false),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', 'teapot'),
        ),
      );
    });
  });

  group('AuthApi.register', () {
    test('maps 409 to user-friendly message', () async {
      final dio = _dioWithRequestHandler((options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 409,
              data: <String, dynamic>{},
            ),
            type: DioExceptionType.badResponse,
          ),
        );
      });

      final api = AuthApi(dio);

      expect(
        () => api.register('alice', 'secret', 'alice', 'a', 'b', 'c', 'salt', null),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Логин или имя пользователя занято. Выберите другой логин/ник.',
          ),
        ),
      );
    });
  });
}
