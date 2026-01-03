class ProfileUser {
  final int id;
  final String login;
  final String username;
  final String? avatar;

  const ProfileUser({
    required this.id,
    required this.login,
    required this.username,
    required this.avatar,
  });

  factory ProfileUser.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return ProfileUser(
      id: m['id'] is int ? m['id'] as int : int.tryParse('${m['id']}') ?? 0,
      login: m['login'] as String? ?? '',
      username: m['username'] as String? ?? '',
      avatar: m['avatar'] as String?,
    );
  }
}
