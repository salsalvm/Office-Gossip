class AppConstants {
  AppConstants._();

  // Network
  static const int connectTimeoutSeconds = 30;
  static const int receiveTimeoutSeconds = 60;
  static const int sendTimeoutSeconds = 60;
  static const int apiTimeoutSeconds = 70;

  /// Email OTP verification UI (sign-up + Profile).
  static const bool emailOtpEnabled = true;

  /// Comment button on posts; hidden until comments are built.
  static const bool commentsEnabled = false;
}
