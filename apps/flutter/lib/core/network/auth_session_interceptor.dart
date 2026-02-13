import 'dart:async';

import 'package:dio/dio.dart';

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/core/constants/keys.dart';
import 'package:ren/core/device/device_metadata.dart';
import 'package:ren/core/secure/secure_storage.dart';

class AuthSessionInterceptor extends Interceptor {
  final Dio _dio;
  final Dio _refreshDio;
  Completer<bool>? _refreshCompleter;

  AuthSessionInterceptor(this._dio) : _refreshDio = Dio();

  bool _isPublicAuthPath(String path) {
    return path.endsWith('/auth/login') ||
        path.endsWith('/auth/register') ||
        path.endsWith('/auth/refresh');
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final metadata = await DeviceMetadataProvider.load();
    options.headers['X-Device-Name'] = metadata.deviceName;
    options.headers['X-App-Version'] = metadata.appVersion;

    if (!_isPublicAuthPath(options.path)) {
      final token = await SecureStorage.readKey(Keys.token);
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;
    final path = err.requestOptions.path;
    final wasRetried =
        err.requestOptions.extra['__retried_after_refresh'] == true;

    if (statusCode != 401 || _isPublicAuthPath(path) || wasRetried) {
      handler.next(err);
      return;
    }

    final refreshed = await _refreshTokens();
    if (!refreshed) {
      await SecureStorage.deleteAllKeys();
      handler.next(err);
      return;
    }

    final newToken = await SecureStorage.readKey(Keys.token);
    if (newToken == null || newToken.isEmpty) {
      handler.next(err);
      return;
    }

    final requestOptions = err.requestOptions;
    requestOptions.extra['__retried_after_refresh'] = true;
    requestOptions.headers['Authorization'] = 'Bearer $newToken';
    final metadata = await DeviceMetadataProvider.load();
    requestOptions.headers['X-Device-Name'] = metadata.deviceName;
    requestOptions.headers['X-App-Version'] = metadata.appVersion;

    try {
      final response = await _dio.fetch(requestOptions);
      handler.resolve(response);
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    }
  }

  Future<bool> _refreshTokens() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();

    try {
      final refreshToken = await SecureStorage.readKey(Keys.refreshToken);
      if (refreshToken == null || refreshToken.isEmpty) {
        _refreshCompleter!.complete(false);
        return _refreshCompleter!.future;
      }

      final metadata = await DeviceMetadataProvider.load();
      final response = await _refreshDio.post(
        '${Apiurl.api}/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(
          headers: {
            'X-Device-Name': metadata.deviceName,
            'X-App-Version': metadata.appVersion,
          },
        ),
      );

      final data =
          (response.data as Map<String, dynamic>? ?? <String, dynamic>{});
      final token = (data['token'] as String? ?? '').trim();
      final newRefresh = (data['refresh_token'] as String? ?? '').trim();
      final sessionId = (data['session_id'] as String? ?? '').trim();

      if (token.isEmpty || newRefresh.isEmpty || sessionId.isEmpty) {
        _refreshCompleter!.complete(false);
        return _refreshCompleter!.future;
      }

      await SecureStorage.writeKey(Keys.token, token);
      await SecureStorage.writeKey(Keys.refreshToken, newRefresh);
      await SecureStorage.writeKey(Keys.sessionId, sessionId);

      _refreshCompleter!.complete(true);
      return _refreshCompleter!.future;
    } catch (_) {
      _refreshCompleter!.complete(false);
      return _refreshCompleter!.future;
    } finally {
      _refreshCompleter = null;
    }
  }
}
