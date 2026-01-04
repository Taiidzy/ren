import 'dart:io';

import 'package:ren/core/constants/api_url.dart';
import 'package:ren/features/profile/data/profile_api.dart';
import 'package:ren/features/profile/domain/profile_user.dart';

class ProfileRepository {
  final ProfileApi api;

  ProfileRepository(this.api);

  Future<ProfileUser> me() async {
    final json = await api.me();
    return _normalize(ProfileUser.fromMap(json));
  }

  Future<ProfileUser> updateUsername(String username) async {
    final json = await api.updateUsername(username);
    return _normalize(ProfileUser.fromMap(json));
  }

  Future<ProfileUser> uploadAvatar(File file) async {
    final json = await api.uploadAvatar(file);
    return _normalize(ProfileUser.fromMap(json));
  }

  Future<ProfileUser> removeAvatar() async {
    final json = await api.removeAvatar();
    return _normalize(ProfileUser.fromMap(json));
  }

  ProfileUser _normalize(ProfileUser u) {
    final avatar = u.avatar;
    final normalizedAvatar = _avatarUrl(avatar);
    return ProfileUser(
      id: u.id,
      login: u.login,
      username: u.username,
      avatar: normalizedAvatar,
    );
  }

  String? _avatarUrl(String? avatarPath) {
    final p = (avatarPath ?? '').trim();
    if (p.isEmpty) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    final normalized = p.startsWith('/') ? p.substring(1) : p;
    return '${Apiurl.api}/avatars/$normalized';
  }
}
