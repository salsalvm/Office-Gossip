import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../logger/app_logger.dart';
import '../network/api_client.dart';
import '../storage/secure_storage_service.dart';
import 'injection_container.dart';

void registerNetwork() {
  sl.registerLazySingleton<ApiClient>(
    () => ApiClient(
      config: sl<AppConfig>(),
      logger: sl<AppLogger>(),
      storage: sl<SecureStorageService>(),
    ),
  );
  sl.registerLazySingleton<Dio>(() => sl<ApiClient>().dio);
}
