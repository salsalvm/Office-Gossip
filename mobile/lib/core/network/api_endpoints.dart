class ApiEndpoints {
  ApiEndpoints._();

  // ── Auth ─────────────────────────────────────────────
  /// POST auth/login — `{ email, password }`
  static const String login = 'auth/login';

  /// POST auth/register — `{ name, email, password, companyName }`
  static const String register = 'auth/register';

  /// POST auth/forgot-password — `{ email }`
  static const String forgotPassword = 'auth/forgot-password';

  /// POST auth/refresh — `{ refreshToken }`
  static const String refresh = 'auth/refresh';

  /// POST auth/logout
  static const String logout = 'auth/logout';

  // ── Me ───────────────────────────────────────────────
  /// GET me
  static const String me = 'me';

  /// PATCH me/profile — `{ displayName, roleTitle?, bio? }`
  static const String meProfile = 'me/profile';

  /// POST me/devices — `{ platform, pushToken }`
  static const String meDevices = 'me/devices';

  // ── Community ────────────────────────────────────────
  static const String communityFeed = 'community/feed';
  static const String communityPeople = 'community/people';

  /// POST community/posts — `{ body, anonymous }`
  static const String communityPosts = 'community/posts';
  static String communityPostLikes(String postId) =>
      'community/posts/$postId/likes';

  /// Endpoints that must not carry a bearer token or trigger a token refresh.
  static const Set<String> public = {
    login,
    register,
    forgotPassword,
    refresh,
  };
}
