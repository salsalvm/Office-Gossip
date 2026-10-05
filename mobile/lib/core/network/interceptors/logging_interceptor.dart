import 'dart:convert';

import 'package:dio/dio.dart';

import '../../logger/app_logger.dart';

class LoggingInterceptor extends Interceptor {
  LoggingInterceptor(this.logger);

  final AppLogger logger;

  static const String _requestStartedAtKey = '_request_started_at';
  static const int _maxBodyLength = 2000;
  static const Set<String> _redactedHeaders = {
    'authorization',
    'cookie',
    'set-cookie',
  };
  static const Set<String> _redactedBodyKeys = {
    'password',
    'accessToken',
    'refreshToken',
    'pushToken',
    'token',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_requestStartedAtKey] = DateTime.now().microsecondsSinceEpoch;

    logger.debug('➡️ API REQUEST');
    logger.debug('URL: ${options.method} ${options.uri}');
    if (options.headers.isNotEmpty) {
      logger.debug('Headers: ${jsonEncode(_redactHeaders(options.headers))}');
    }
    if (options.queryParameters.isNotEmpty) {
      logger.debug('Query Params: ${jsonEncode(options.queryParameters)}');
    }
    if (options.data != null) {
      logger.debug('Body: ${_format(options.data)}');
    }
    logger.debug('cURL:\n${_buildCurlCommand(options)}');

    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    logger.success('✅ API RESPONSE');
    logger.success(
      'Status: ${response.statusCode} | ${response.requestOptions.method} '
      '${response.requestOptions.path} | ${_elapsedMs(response.requestOptions)} ms',
    );
    if (response.data != null) {
      logger.success('Response: ${_format(response.data)}');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger.error('❌ API ERROR');
    logger.error('URL: ${err.requestOptions.method} ${err.requestOptions.uri}');
    logger.error('Message: ${err.message}');
    if (err.response != null) {
      logger.error(
        'Status: ${err.response?.statusCode} | ${err.requestOptions.path} | '
        '${_elapsedMs(err.requestOptions)} ms',
      );
      if (err.response?.data != null) {
        logger.error('Error Response: ${_format(err.response?.data)}');
      }
    }
    logger.error('cURL:\n${_buildCurlCommand(err.requestOptions)}');
    handler.next(err);
  }

  int _elapsedMs(RequestOptions options) {
    final Object? startedAt = options.extra[_requestStartedAtKey];
    if (startedAt is! int) return 0;
    final elapsedMicros = DateTime.now().microsecondsSinceEpoch - startedAt;
    return (elapsedMicros / Duration.microsecondsPerMillisecond).round();
  }

  Map<String, dynamic> _redactHeaders(Map<String, dynamic> headers) =>
      headers.map((key, value) => MapEntry(
          key, _redactedHeaders.contains(key.toLowerCase()) ? '***' : value));

  Object? _redact(Object? value) {
    if (value is Map) {
      return value.map((key, v) =>
          MapEntry(key, _redactedBodyKeys.contains(key) ? '***' : _redact(v)));
    }
    if (value is List) return value.map(_redact).toList();
    return value;
  }

  String _format(Object? data) {
    String output;
    try {
      output = const JsonEncoder.withIndent('  ').convert(_redact(data));
    } on Object {
      output = data.toString();
    }
    return output.length > _maxBodyLength
        ? '${output.substring(0, _maxBodyLength)}… (${output.length} chars)'
        : output;
  }

  String _buildCurlCommand(RequestOptions options) {
    final buffer = StringBuffer('curl -X ${options.method.toUpperCase()} ');
    buffer.write(_shellSingleQuote(options.uri.toString()));
    _redactHeaders(options.headers).forEach((key, value) {
      if (value != null) {
        buffer.write('\n  -H ${_shellSingleQuote('$key: $value')}');
      }
    });
    if (options.data != null) {
      final body = options.data is String
          ? options.data as String
          : jsonEncode(_redact(options.data));
      buffer.write('\n  -d ${_shellSingleQuote(body)}');
    }
    return buffer.toString();
  }

  String _shellSingleQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";
}
