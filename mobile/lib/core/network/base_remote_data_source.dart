import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import '../error/exceptions.dart';
import 'api_error_message.dart';

/// Wraps Dio calls so remote data sources only ever throw [AppException]s.
abstract class BaseRemoteDataSource {
  Future<T> safeApiCall<T>(
    Future<T> Function() apiCall, {
    Duration? timeout,
  }) async {
    try {
      return await apiCall().timeout(
        timeout ?? const Duration(seconds: AppConstants.apiTimeoutSeconds),
        onTimeout: () =>
            throw NetworkException('Request timed out. Please try again.'),
      );
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    } on AppException {
      rethrow;
    } catch (e) {
      throw ServerException(ApiErrorMessage.sanitizeOrDefault(e.toString()));
    }
  }

  List<T> mapList<T>(
    Object? data,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return (data as List<dynamic>? ?? const <dynamic>[])
        .map((item) => fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }
}
