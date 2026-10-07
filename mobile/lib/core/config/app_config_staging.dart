import '../env/app_environment.dart';
import 'app_config.dart';

class StagingAppConfig implements AppConfig {
  @override
  AppEnvironment get environment => AppEnvironment.staging;

  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: hostedApiBaseUrl,
  );
  static const String _apiPath = 'api';

  @override
  String get apiBaseUrl => '$_baseUrl/$_apiPath/';

  @override
  bool get enableLogging => true;
}
