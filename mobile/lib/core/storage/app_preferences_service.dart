import '../auth/data/models/app_user_model.dart';

abstract interface class AppPreferencesService {
  Future<void> saveUser(AppUserModel user);
  AppUserModel? getUser();
  Future<void> clearUser();
}
