class ApiHeaders {
  ApiHeaders._();

  static const String authorization = 'Authorization';
  static const String bearer = 'Bearer';

  static const String contentType = 'Content-Type';
  static const String applicationJson = 'application/json';

  static const String accept = 'Accept';
  static const String acceptJson = 'application/json';

  static String? bearerAuthorization(String? rawToken) {
    final token = rawToken?.trim();
    if (token == null || token.isEmpty) return null;
    return '$bearer $token';
  }
}
