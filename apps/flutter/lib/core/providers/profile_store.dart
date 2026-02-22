import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:ren/features/profile/data/profile_repository.dart';
import 'package:ren/features/profile/domain/profile_user.dart';

class ProfileStore extends ChangeNotifier {
  ProfileRepository repo;

  ProfileUser? user;
  bool isLoading = false;
  String? error;

  ProfileStore(this.repo);

  ProfileUser _bustAvatarCache(ProfileUser u) {
    final avatar = u.avatar;
    if (avatar == null || avatar.trim().isEmpty) return u;

    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    Uri? uri;
    try {
      uri = Uri.parse(avatar);
    } catch (_) {
      uri = null;
    }
    if (uri == null) return u;

    final nextUri = uri.replace(
      queryParameters: <String, String>{...uri.queryParameters, 'v': ts},
    );

    return ProfileUser(
      id: u.id,
      login: u.login,
      username: u.username,
      avatar: nextUri.toString(),
    );
  }

  void setRepo(ProfileRepository next) {
    repo = next;
  }

  void resetSession() {
    user = null;
    isLoading = false;
    error = null;
    notifyListeners();
  }

  Future<void> loadMe() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      user = await repo.me();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> changeUsername(String username) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      user = await repo.updateUsername(username);
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> changeNickname(String nickname) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      user = await repo.updateNickname(nickname);
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> setAvatar(File file) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final updated = await repo.uploadAvatar(file);
      user = _bustAvatarCache(updated);
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> removeAvatar() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      user = await repo.removeAvatar();
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
