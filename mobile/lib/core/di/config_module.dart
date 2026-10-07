import '../config/app_config.dart';
import '../config/app_config_dev.dart';
import '../config/app_config_prod.dart';
import '../config/app_config_staging.dart';
import '../env/app_environment.dart';
import 'injection_container.dart';

void registerConfig() {
  final AppConfig config = switch (sl<AppEnvironment>()) {
    AppEnvironment.dev => DevAppConfig(),
    AppEnvironment.staging => StagingAppConfig(),
    AppEnvironment.prod => ProdAppConfig(),
  };
  sl.registerSingleton<AppConfig>(config);
}
