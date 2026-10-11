import '../../../utils/type_def.dart';
import '../entities/app_user.dart';
import '../entities/deactivated_account.dart';
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
    String? companyId,
    String? companyName,
    String? companyWebsite,
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

  /// Joins a listed company ([companyId]) or requests a new one ([companyName]).
  ResultFuture<AppUser> chooseCompany({
    String? companyId,
    String? companyName,
    String? companyWebsite,
  });

  /// Reactivates a deleted account with its credentials and signs in.
  ResultFuture<Session> restoreAccount({
    required String email,
    required String password,
  });

  /// Deactivates the signed-in account (re-checking [password]) and clears
  /// the local session. It is purged after the grace period unless restored.
  ResultFuture<AccountDeletion> deleteAccount({
    required String password,
    String? reason,
  });

  ResultFuture<int> accountGraceDays();
}
