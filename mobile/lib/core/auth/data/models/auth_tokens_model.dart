import '../../domain/entities/session.dart';
import 'app_user_model.dart';

class AuthTokensModel {
  const AuthTokensModel({
    this.accessToken,
    this.refreshToken,
    this.confirmationRequired = false,
    this.user,
  });

  factory AuthTokensModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    return AuthTokensModel(
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      confirmationRequired: json['confirmationRequired'] as bool? ?? false,
      user: user is Map
          ? AppUserModel.fromJson(Map<String, dynamic>.from(user))
          : null,
    );
  }

  final String? accessToken;
  final String? refreshToken;
  final bool confirmationRequired;
  final AppUserModel? user;

  Session? toSession() => accessToken == null
      ? null
      : Session(
          accessToken: accessToken!,
          refreshToken: refreshToken,
          user: user,
        );
}
