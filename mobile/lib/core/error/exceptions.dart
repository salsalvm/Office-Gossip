import 'package:dio/dio.dart';

import '../network/api_error_message.dart';

abstract class AppException implements Exception {
  AppException(this.message, {this.statusCode});

  factory AppException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return NetworkException('Request timed out. Please try again.');

      case DioExceptionType.connectionError:
        return NetworkException('No internet connection. Please try again.');

      case DioExceptionType.badResponse:
        final int? statusCode = e.response?.statusCode;
        final String message = ApiErrorMessage.userFacing(
          e.response?.data,
          fallback: e.message,
        );
        if (statusCode == 401) {
          return AuthException(
            ApiErrorMessage.fromResponseBody(e.response?.data) ??
                'Session expired. Please sign in again.',
            statusCode: statusCode,
          );
        }
        return ServerException(message, statusCode: statusCode);

      case DioExceptionType.cancel:
        return NetworkException('Request cancelled');

      case DioExceptionType.badCertificate:
        return UnknownException('Bad certificate error occurred');

      case DioExceptionType.unknown:
        return UnknownException('Unexpected error occurred');
    }
  }

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  NetworkException(super.message);
}

class ServerException extends AppException {
  ServerException(super.message, {super.statusCode});
}

class AuthException extends AppException {
  AuthException(super.message, {super.statusCode});
}

class CacheException extends AppException {
  CacheException(super.message);
}

class DeviceException extends AppException {
  DeviceException(super.message);
}

class UnknownException extends AppException {
  UnknownException(super.message);
}
