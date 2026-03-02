import 'package:ren/features/auth/data/auth_api.dart';
import 'package:ren/features/auth/domain/auth_user.dart';
import 'package:ren/features/auth/domain/auth_models.dart';

import 'package:ren/core/secure/secure_storage.dart';
import 'package:ren/core/constants/keys.dart';

import 'package:ren/core/e2ee/signal_protocol_client.dart';

class AuthRepository {
  final AuthApi api;
  final SignalProtocolClient signal;

  AuthRepository(this.api, this.signal);

  Future<AuthUser> login(String login, String password, bool rememberMe) async {
    final json = await api.login(login, password, rememberMe);

    final resp = LoginResponse.fromMap(json);

    await SecureStorage.writeKey(Keys.token, resp.token);
    await SecureStorage.writeKey(Keys.refreshToken, resp.refreshToken);
    await SecureStorage.writeKey(Keys.sessionId, resp.sessionId);
    await SecureStorage.writeKey(Keys.userId, resp.user.id.toString());
    final bundle = await signal.initUser(userId: resp.user.id);
    if (bundle.isNotEmpty) {
      await api.updateSignalBundle(bundle);
    }

    return AuthUser(
      id: resp.user.id,
      login: resp.user.login,
      username: resp.user.username,
      nickname: resp.user.nickname,
      avatar: resp.user.avatar,
      pkebymk: resp.user.pkebymk,
      pkebyrk: resp.user.pkebyrk,
      pubk: resp.user.pubk,
      token: resp.token,
      refreshToken: resp.refreshToken,
      sessionId: resp.sessionId,
    );
  }

  Future<RegisterUser> register(
    String login,
    String password,
    String recoveryKey,
    String? nickname,
    String username,
  ) async {
    // Вызываем API register. Порядок аргументов: login, password, username, ...
    final json = await api.register(
      login,
      password,
      username,
      '',
      '',
      '',
      '',
      nickname,
    );

    final registeredId = int.tryParse('${json['id'] ?? ''}') ?? 0;
    if (registeredId > 0) {
      final bundle = await signal.initUser(userId: registeredId);
      if (bundle.isNotEmpty) {
        await api.updateSignalBundle(bundle);
      }
    }

    return RegisterUser(
      id: (json['id'] ?? '').toString(),
      login: (json['login'] ?? login).toString(),
      username: (json['username'] ?? username).toString(),
      pkebymk: (json['pkebymk'] ?? '').toString(),
      pkebyrk: (json['pkebyrk'] ?? '').toString(),
      pubk: (json['pubk'] ?? '').toString(),
      salt: (json['salt'] ?? '').toString(),
    );
  }

  Future<Map<String, dynamic>> updateNickname(String nickname) async {
    return await api.updateNickname(nickname);
  }

  Future<List<dynamic>> searchUsers(String query, {int limit = 10}) async {
    return await api.searchUsers(query, limit: limit);
  }
}
