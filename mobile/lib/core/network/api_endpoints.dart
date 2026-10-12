class ApiEndpoints {
  ApiEndpoints._();

  // ── Auth ─────────────────────────────────────────────
  /// POST auth/login — `{ email, password }`
  static const String login = 'auth/login';

  /// POST auth/register — `{ name, email, password }` plus either `companyId`
  /// or `{ companyName, companyWebsite? }` to request a new company.
  static const String register = 'auth/register';

  /// GET — active companies `[{ id, name }]` members can join at sign-up.
  static const String publicCompanies = 'public/companies';

  /// POST — `{ email, name? }`; emails a sign-up verification code.
  static const String emailSendOtp = 'auth/email/send-otp';

  /// POST — `{ email, code }`; returns `{ verificationToken }` for register.
  static const String emailVerifyOtp = 'auth/email/verify-otp';

  /// POST auth/forgot-password — `{ email }`
  static const String forgotPassword = 'auth/forgot-password';

  /// POST auth/refresh — `{ refreshToken }`
  static const String refresh = 'auth/refresh';

  /// POST auth/logout
  static const String logout = 'auth/logout';

  /// POST — `{ email, password }`; reactivates a deleted account within its
  /// grace period and returns a session like [login].
  static const String restoreAccount = 'auth/restore';

  /// GET — `{ graceDays }` before a deleted account is permanently erased.
  static const String accountPolicy = 'public/account-policy';

  // ── Me ───────────────────────────────────────────────
  /// GET me
  static const String me = 'me';

  /// PATCH me/profile — `{ displayName, roleTitle?, bio? }`
  static const String meProfile = 'me/profile';

  /// POST — `{ companyId }` joins a listed company, or
  /// `{ companyName, companyWebsite? }` requests a new one. Returns `{ user }`.
  static const String meCompany = 'me/company';

  /// DELETE — `{ password, reason? }`; deactivates the account and schedules
  /// its permanent deletion. Returns `{ purgeAfter, graceDays }`.
  static const String meAccount = 'me/account';

  /// POST me/devices — `{ platform, pushToken }`
  static const String meDevices = 'me/devices';

  /// POST — emails the member a one-time verification code.
  static const String meEmailSendOtp = 'me/email/send-otp';

  /// POST me/email/verify-otp — `{ code }`; marks the email verified.
  static const String meEmailVerifyOtp = 'me/email/verify-otp';

  /// GET — likes and comments on the member's posts, newest first.
  static const String notifications = 'notifications';

  /// POST — marks every notification as read.
  static const String notificationsRead = 'notifications/read';

  // ── Community ────────────────────────────────────────
  static const String communityFeed = 'community/feed';

  /// GET — admin flash updates addressed to the signed-in member.
  static const String announcements = 'announcements';
  static const String communityPeople = 'community/people';

  /// POST community/posts — `{ body, anonymous, poll? }` (2–4 option labels)
  static const String communityPosts = 'community/posts';
  static String communityPostLikes(String postId) =>
      'community/posts/$postId/likes';

  /// POST `{ reaction: love|laugh|fire|clap|wow|null }` → `{ reactions, myReaction, likes, liked }`.
  static String communityPostReactions(String postId) =>
      'community/posts/$postId/reactions';

  /// GET `?scope=` — popular #hashtags in recent posts: `[{ tag, posts }]`.
  static const String communityTopics = 'community/topics';

  /// PATCH `{ body }` edits, DELETE removes — author only.
  static String communityPost(String postId) => 'community/posts/$postId';

  /// POST community/posts/:id/archive — `{ archived }`, author only.
  static String communityPostArchive(String postId) =>
      'community/posts/$postId/archive';

  /// POST community/posts/:id/report — `{ reason }`
  static String communityPostReport(String postId) =>
      'community/posts/$postId/report';

  /// POST — `{ optionId }` votes (again to move the vote), `null` takes it back.
  /// Returns `{ poll }`.
  static String communityPostVote(String postId) =>
      'community/posts/$postId/vote';

  /// POST — `{ saved }` bookmarks or un-bookmarks a post.
  static String communityPostSave(String postId) =>
      'community/posts/$postId/save';

  /// POST — `{ kind: 'block' | 'mute' }` for the post's author, without
  /// revealing who wrote an anonymous post.
  static String communityPostBlock(String postId) =>
      'community/posts/$postId/block';

  /// POST `{ kind }` blocks or mutes a member; DELETE undoes it.
  static String communityPersonBlock(String userId) =>
      'community/people/$userId/block';

  /// GET — the member's saved posts, newest save first.
  static const String meSaved = 'me/saved';

  /// GET — blocked and muted members; DELETE `me/blocks/:id` removes one.
  static const String meBlocks = 'me/blocks';
  static String meBlock(String id) => 'me/blocks/$id';

  /// Endpoints that must not carry a bearer token or trigger a token refresh.
  static const Set<String> public = {
    login,
    register,
    publicCompanies,
    forgotPassword,
    refresh,
    emailSendOtp,
    emailVerifyOtp,
    restoreAccount,
    accountPolicy,
  };
}
