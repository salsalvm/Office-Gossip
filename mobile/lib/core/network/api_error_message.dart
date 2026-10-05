import 'dart:convert';

class ApiErrorMessage {
  ApiErrorMessage._();

  static const String defaultMessage =
      'Something went wrong. Please try again.';

  /// Reads `message` / `error` from an API error body (map or JSON string).
  static String? fromResponseBody(dynamic data) {
    if (data is Map) {
      return _read(data['message']) ?? _read(data['error']);
    }
    if (data is String && data.trim().isNotEmpty) {
      try {
        return fromResponseBody(jsonDecode(data));
      } on FormatException {
        return _read(data);
      }
    }
    return null;
  }

  /// Prefer API copy; never surface Dio / stack-style technical text to users.
  static String userFacing(dynamic responseBody, {String? fallback}) =>
      fromResponseBody(responseBody) ?? _read(fallback) ?? defaultMessage;

  static String sanitizeOrDefault(String? message) =>
      _read(message) ?? defaultMessage;

  static String? _read(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || _looksLikeTechnicalLeak(text)) return null;
    return text;
  }

  static bool _looksLikeTechnicalLeak(String message) {
    final lower = message.toLowerCase();
    return lower.contains('dioexception') ||
        lower.contains('validatestatus') ||
        lower.contains('status code of') ||
        lower.contains('package:dio/') ||
        lower.startsWith('#0 ') ||
        lower.startsWith('<!doctype') ||
        (lower.contains('exception') && lower.contains('was thrown'));
  }
}
