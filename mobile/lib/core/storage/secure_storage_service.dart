abstract interface class SecureStorageService {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({required String accessToken, String? refreshToken});
  Future<void> clearTokens();
}
