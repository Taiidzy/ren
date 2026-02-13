class ApiUser {
  final int id;
  final String login;
  final String? username;
  final String? avatar;
  final String? pkebymk;
  final String? pkebyrk;
  final String? salt;
  final String? pubk;

  ApiUser({
    required this.id,
    required this.login,
    this.username,
    this.avatar,
    this.pkebymk,
    this.pkebyrk,
    this.salt,
    this.pubk,
  });

  factory ApiUser.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return ApiUser(
      id: m['id'] is int ? m['id'] as int : int.tryParse('${m['id']}') ?? 0,
      login: m['login'] as String? ?? '',
      username: m['username'] as String?,
      avatar: m['avatar'] as String?,
      pkebymk: m['pkebymk'] as String?,
      pkebyrk: m['pkebyrk'] as String?,
      salt: m['salt'] as String?,
      pubk: m['pubk'] as String?,
    );
  }
}

class LoginResponse {
  final String? message;
  final String token;
  final String refreshToken;
  final String sessionId;
  final ApiUser user;

  LoginResponse({
    this.message,
    required this.token,
    required this.refreshToken,
    required this.sessionId,
    required this.user,
  });

  factory LoginResponse.fromMap(Map<String, dynamic> map) {
    return LoginResponse(
      message: map['message'] as String?,
      token: map['token'] as String? ?? '',
      refreshToken: map['refresh_token'] as String? ?? '',
      sessionId: map['session_id'] as String? ?? '',
      user: ApiUser.fromMap(map['user'] as Map<String, dynamic>?),
    );
  }
}
