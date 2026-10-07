import 'package:dio/dio.dart';

import '../../constants/api_headers.dart';
import '../../logger/app_logger.dart';
import '../../storage/secure_storage_service.dart';
import '../api_endpoints.dart';

/// Attaches the bearer token and transparently refreshes it once on 401.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required Dio plainDio,
    required SecureStorageService storage,
    required AppLogger logger,
  })  : _plainDio = plainDio,
        _storage = storage,
        _logger = logger;

  /// Interceptor-free client for the refresh call and the retried request, so
  /// neither re-enters this queued interceptor.
  final Dio _plainDio;
  final SecureStorageService _storage;
  final AppLogger _logger;

  static const String _retriedKey = '_auth_retried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isPublic(options)) {
      final authorization =
          ApiHeaders.bearerAuthorization(await _storage.readAccessToken());
      if (authorization != null) {
        options.headers[ApiHeaders.authorization] = authorization;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final shouldRefresh = err.response?.statusCode == 401 &&
        !_isPublic(options) &&
        options.extra[_retriedKey] != true;
    if (!shouldRefresh) return handler.next(err);

    final newToken = await _refreshAccessToken();
    if (newToken == null) return handler.next(err);

    try {
      options.extra[_retriedKey] = true;
      options.headers[ApiHeaders.authorization] =
          ApiHeaders.bearerAuthorization(newToken);
      handler.resolve(await _plainDio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<String?> _refreshAccessToken() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) {
      await _storage.clearTokens();
      return null;
    }
    try {
      final response = await _plainDio.post<Map<String, dynamic>>(
        ApiEndpoints.refresh,
        data: {'refreshToken': refreshToken},
      );
      final data = response.data ?? const <String, dynamic>{};
      final accessToken = data['accessToken'] as String;
      await _storage.saveTokens(
        accessToken: accessToken,
        refreshToken: data['refreshToken'] as String?,
      );
      return accessToken;
    } on Object catch (error) {
      _logger.warning('Token refresh failed: $error');
      await _storage.clearTokens();
      return null;
    }
  }

  bool _isPublic(RequestOptions options) =>
      ApiEndpoints.public.contains(options.path);
}
