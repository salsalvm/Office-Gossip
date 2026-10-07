import '../env/app_environment.dart';

/// Mac's LAN address running the backend. Changes when you switch Wi-Fi or
/// hotspot — find it with `ipconfig getifaddr en0`. Override per run with
/// `--dart-define=API_BASE_URL=http://<ip>:4000`.
const String defaultApiBaseUrl = 'http://172.20.10.3:4000';

/// Firebase-hosted API used by staging and production builds.
const String hostedApiBaseUrl = 'https://office-gossip-api.web.app';

abstract class AppConfig {
  AppEnvironment get environment;

  /// API base including the trailing `api/` segment, e.g. `http://localhost:4000/api/`.
  String get apiBaseUrl;

  bool get enableLogging;
}
