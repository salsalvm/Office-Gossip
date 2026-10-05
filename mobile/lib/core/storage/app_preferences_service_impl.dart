import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../auth/data/models/app_user_model.dart';
import '../constants/storage_keys.dart';
import 'app_preferences_service.dart';

class AppPreferencesServiceImpl implements AppPreferencesService {
  AppPreferencesServiceImpl(this._prefs);
  final SharedPreferences _prefs;

  @override
  Future<void> saveUser(AppUserModel user) =>
      _prefs.setString(StorageKeys.user, jsonEncode(user.toJson()));

  @override
  AppUserModel? getUser() {
    final raw = _prefs.getString(StorageKeys.user);
    if (raw == null) return null;
    try {
      return AppUserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> clearUser() => _prefs.remove(StorageKeys.user);
}
