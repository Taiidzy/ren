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

  void setRepo(ProfileRepository next) {
    repo = next;
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

  Future<bool> setAvatar(File file) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      user = await repo.uploadAvatar(file);
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
