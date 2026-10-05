import '../config/app_config.dart';
import '../logger/app_logger.dart';
import '../logger/logger_service.dart';
import 'injection_container.dart';

void registerLogger() {
  sl.registerLazySingleton<AppLogger>(
    () => LoggerService(enableLogging: sl<AppConfig>().enableLogging),
  );
}
