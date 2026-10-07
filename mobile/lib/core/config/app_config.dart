import '../env/app_environment.dart';

/// Vercel-hosted API (backend/vercel.json), used by every build by default.
const String hostedApiBaseUrl = 'https://office-gossip-api.vercel.app';

/// Dev builds use the hosted API too. To hit a backend running on your Mac,
/// pass `--dart-define=API_BASE_URL=http://<mac-ip>:4000` (`ipconfig getifaddr en0`).
const String defaultApiBaseUrl = hostedApiBaseUrl;

abstract class AppConfig {
  AppEnvironment get environment;

  /// API base including the trailing `api/` segment, e.g. `http://localhost:4000/api/`.
  String get apiBaseUrl;

  bool get enableLogging;
}
