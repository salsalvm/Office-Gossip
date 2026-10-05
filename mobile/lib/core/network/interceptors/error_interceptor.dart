import 'package:dio/dio.dart';

import '../../logger/app_logger.dart';

class ErrorInterceptor extends Interceptor {
  ErrorInterceptor(this.logger);
  final AppLogger logger;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger.error('Network error', error: err, stackTrace: err.stackTrace);
    handler.next(err);
  }
}
