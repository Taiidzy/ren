import 'dart:async';

import 'package:dio/dio.dart';

class ServerRetryInterceptor extends Interceptor {
  static const String _attemptKey = '__server_retry_attempt';
  static const String _disableKey = '__disable_server_retry';

  final Dio _dio;

  ServerRetryInterceptor(this._dio);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_shouldRetry(err)) {
      handler.next(err);
      return;
    }

    var lastError = err;
    var attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 0;

    while (true) {
      if (lastError.requestOptions.cancelToken?.isCancelled == true) {
        handler.next(lastError);
        return;
      }

      attempt += 1;
      final delay = _delayForAttempt(attempt);
      await Future<void>.delayed(delay);

      final requestOptions = lastError.requestOptions;
      requestOptions.extra[_attemptKey] = attempt;

      try {
        final response = await _dio.fetch(requestOptions);
        handler.resolve(response);
        return;
      } on DioException catch (nextError) {
        if (!_shouldRetry(nextError)) {
          handler.next(nextError);
          return;
        }
        lastError = nextError;
      }
    }
  }

  bool _shouldRetry(DioException err) {
    if (err.requestOptions.extra[_disableKey] == true) {
      return false;
    }
    if (err.type == DioExceptionType.cancel) {
      return false;
    }
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    return err.response == null;
  }

  Duration _delayForAttempt(int attempt) {
    if (attempt <= 1) return const Duration(seconds: 10);
    if (attempt == 2) return const Duration(seconds: 30);
    return const Duration(minutes: 1);
  }
}
