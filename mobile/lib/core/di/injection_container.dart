import 'package:get_it/get_it.dart';

import '../../features/feed/dependency_injection.dart';
import '../../features/notifications/dependency_injection.dart';
import '../../features/people/dependency_injection.dart';
import '../../features/profile/dependency_injection.dart';
import '../auth/dependency_injection.dart';
import '../env/app_environment.dart';
import 'config_module.dart';
import 'env_module.dart';
import 'logger_module.dart';
import 'network_module.dart';
import 'storage_module.dart';

final GetIt sl = GetIt.instance;

Future<void> initDI(AppEnvironment env, {required bool firebaseReady}) async {
  registerEnv(env);
  registerConfig();
  registerLogger();
  await registerStorage();
  registerNetwork();

  registerAuthFeature();
  registerFeedFeature();
  registerPeopleFeature();
  registerProfileFeature();
  registerNotificationsFeature(firebaseReady: firebaseReady);
}
