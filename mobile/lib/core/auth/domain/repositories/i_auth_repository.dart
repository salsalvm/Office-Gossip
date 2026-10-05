import '../../../utils/type_def.dart';
import '../entities/app_user.dart';
import '../entities/session.dart';

abstract interface class IAuthRepository {
  ResultFuture<Session?> restoreSession();

  ResultFuture<Session> signIn({
    required String email,
    required String password,
  });

  ResultVoid requestPasswordReset({required String email});

  ResultFuture<RegistrationResult> register({
    required String name,
    required String email,
    required String password,
    required String companyName,
    String? verificationToken,
  });

  ResultVoid signOut();

  /// Fetches the latest profile from the API and caches it locally.
  ResultFuture<AppUser> refreshUser();

  ResultFuture<AppUser> updateProfile({
    required String displayName,
    String? roleTitle,
    String? bio,
  });
}
