import 'app_user.dart';

class Session {
  const Session({required this.accessToken, this.refreshToken, this.user});
  final String accessToken;
  final String? refreshToken;
  final AppUser? user;

  Session copyWith({AppUser? user}) => Session(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: user ?? this.user);
}

class RegistrationResult {
  const RegistrationResult({this.session, required this.confirmationRequired});
  final Session? session;
  final bool confirmationRequired;
}
