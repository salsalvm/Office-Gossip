import '../env/app_environment.dart';
import 'injection_container.dart';

void registerEnv(AppEnvironment env) {
  sl.registerSingleton<AppEnvironment>(env);
}
