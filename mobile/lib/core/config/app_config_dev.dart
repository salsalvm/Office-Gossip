import '../env/app_environment.dart';
import 'app_config.dart';

class DevAppConfig implements AppConfig {
  @override
  AppEnvironment get environment => AppEnvironment.dev;

  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://172.20.10.3:4000',
  );
  static const String _apiPath = 'api';

  @override
  String get apiBaseUrl => '$_baseUrl/$_apiPath/';

  @override
  bool get enableLogging => true;
}
