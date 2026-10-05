import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/app_preferences_service.dart';
import '../storage/app_preferences_service_impl.dart';
import '../storage/cache_store.dart';
import '../storage/secure_storage_service.dart';
import '../storage/secure_storage_service_impl.dart';
import 'injection_container.dart';

Future<void> registerStorage() async {
  sl.registerLazySingleton<FlutterSecureStorage>(
    () => const FlutterSecureStorage(),
  );
  sl.registerLazySingleton<SecureStorageService>(
    () => SecureStorageServiceImpl(sl<FlutterSecureStorage>()),
  );

  final prefs = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(prefs);
  sl.registerLazySingleton<AppPreferencesService>(
    () => AppPreferencesServiceImpl(sl<SharedPreferences>()),
  );
  sl.registerLazySingleton<CacheStore>(
    () => SharedPrefsCacheStore(sl<SharedPreferences>()),
  );
}
