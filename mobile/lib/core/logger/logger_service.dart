import 'dart:developer';

import 'app_logger.dart';

class LoggerService implements AppLogger {
  LoggerService({required this.enableLogging});
  final bool enableLogging;

  @override
  void success(String message) {
    if (enableLogging) log('✅ SUCCESS: $message', name: 'SUCCESS');
  }

  @override
  void debug(String message) {
    if (enableLogging) log('🐛 DEBUG: $message', name: 'DEBUG');
  }

  @override
  void info(String message) {
    if (enableLogging) log('ℹ️ INFO: $message', name: 'INFO');
  }

  @override
  void warning(String message) {
    if (enableLogging) log('⚠️ WARNING: $message', name: 'WARNING');
  }

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    if (!enableLogging) return;
    log('❌ ERROR: $message',
        name: 'ERROR', error: error, stackTrace: stackTrace);
  }
}
