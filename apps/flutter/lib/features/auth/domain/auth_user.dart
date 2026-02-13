class AuthUser {
  final int id;
  final String login;
  final String? username;
  final String? avatar;
  final String? pkebymk;
  final String? pkebyrk;
  final String? pubk;
  final String token;
  final String refreshToken;
  final String sessionId;

  AuthUser({
    required this.id,
    required this.login,
    this.username,
    this.avatar,
    this.pkebymk,
    this.pkebyrk,
    this.pubk,
    required this.token,
    required this.refreshToken,
    required this.sessionId,
  });
}

class RegisterUser {
  final String id;
  final String login;
  final String username;
  final String pkebymk;
  final String pkebyrk;
  final String pubk;
  final String salt;

  RegisterUser({
    required this.id,
    required this.login,
    required this.username,
    required this.pkebymk,
    required this.pkebyrk,
    required this.pubk,
    required this.salt,
  });
}
