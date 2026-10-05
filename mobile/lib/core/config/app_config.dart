import '../env/app_environment.dart';

abstract class AppConfig {
  AppEnvironment get environment;

  /// API base including the trailing `api/` segment, e.g. `http://localhost:4000/api/`.
  String get apiBaseUrl;

  bool get enableLogging;
}
