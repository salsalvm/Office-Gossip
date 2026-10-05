import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../constants/api_headers.dart';
import '../constants/app_constants.dart';
import '../logger/app_logger.dart';
import '../storage/secure_storage_service.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/logging_interceptor.dart';

class ApiClient {
  ApiClient({
    required AppConfig config,
    required AppLogger logger,
    required SecureStorageService storage,
  }) {
    final options = BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout:
          const Duration(seconds: AppConstants.connectTimeoutSeconds),
      receiveTimeout:
          const Duration(seconds: AppConstants.receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: AppConstants.sendTimeoutSeconds),
      headers: const <String, dynamic>{
        ApiHeaders.contentType: ApiHeaders.applicationJson,
        ApiHeaders.accept: ApiHeaders.acceptJson,
      },
    );

    logger.info(
        'API base URL (${config.environment.name}): ${config.apiBaseUrl}');
    dio = Dio(options);
    dio.interceptors.addAll(<Interceptor>[
      AuthInterceptor(
        plainDio: Dio(options),
        storage: storage,
        logger: logger,
      ),
      if (config.enableLogging) LoggingInterceptor(logger),
      ErrorInterceptor(logger),
    ]);
  }

  late final Dio dio;
}
