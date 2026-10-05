import '../../../storage/cache_store.dart';
import 'package:fpdart/fpdart.dart';

import '../../../error/exceptions.dart';
import '../../../network/base_repository.dart';
import '../../../storage/app_preferences_service.dart';
import '../../../storage/secure_storage_service.dart';
import '../../../utils/type_def.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/session.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/auth_tokens_model.dart';

class AuthRepositoryImpl extends BaseRepository implements IAuthRepository {
  AuthRepositoryImpl(
      this._remoteDataSource, this._storage, this._preferences, this._cache);

  final IAuthRemoteDataSource _remoteDataSource;
  final SecureStorageService _storage;
  final AppPreferencesService _preferences;
  final CacheStore _cache;

  @override
  ResultFuture<Session?> restoreSession() {
    return handleRequest(() async {
      if (await _storage.readAccessToken() == null) return null;
      try {
        await _preferences.saveUser(await _remoteDataSource.getCurrentUser());
      } on AuthException {
        await _clearLocalSession();
        return null;
      } on AppException catch (e) {
        // 403: the account (e.g. the admin) isn't allowed in the member app.
        if (e.statusCode == 403) {
          await _clearLocalSession();
          return null;
        }
        // Retain a saved session while offline; it is refreshed on next use.
      }
      final accessToken = await _storage.readAccessToken();
      if (accessToken == null) {
        await _preferences.clearUser();
        return null;
      }
      return Session(
        accessToken: accessToken,
        refreshToken: await _storage.readRefreshToken(),
        user: _preferences.getUser(),
      );
    });
  }

  @override
  ResultFuture<Session> signIn({
    required String email,
    required String password,
  }) {
    return handleRequest(() async {
      final tokens =
          await _remoteDataSource.login(email: email, password: password);
      final session = tokens.toSession();
      if (session == null) {
        throw ServerException('Sign in failed. Please try again.');
      }
      await _persist(tokens);
      return session;
    });
  }

  @override
  ResultVoid requestPasswordReset({required String email}) {
    return handleRequest(() async {
      await _remoteDataSource.requestPasswordReset(email: email);
      return unit;
    });
  }

  @override
  ResultFuture<RegistrationResult> register({
    required String name,
    required String email,
    required String password,
    required String companyName,
  }) {
    return handleRequest(() async {
      final tokens = await _remoteDataSource.register(
        name: name,
        email: email,
        password: password,
        companyName: companyName,
      );
      await _persist(tokens);
      return RegistrationResult(
        session: tokens.toSession(),
        confirmationRequired: tokens.confirmationRequired,
      );
    });
  }

  @override
  ResultVoid signOut() {
    return handleRequest(() async {
      try {
        await _remoteDataSource.logout();
      } on AppException {
        // Clear the local session even if the API is unavailable.
      } finally {
        await _clearLocalSession();
      }
      return unit;
    });
  }

  @override
  ResultFuture<AppUser> refreshUser() {
    return handleRequest(() async {
      final user = await _remoteDataSource.getCurrentUser();
      await _preferences.saveUser(user);
      return user;
    });
  }

  @override
  ResultFuture<AppUser> updateProfile({
    required String displayName,
    String? roleTitle,
    String? bio,
  }) {
    return handleRequest(() async {
      await _remoteDataSource.updateProfile(
          displayName: displayName, roleTitle: roleTitle, bio: bio);
      final user = await _remoteDataSource.getCurrentUser();
      await _preferences.saveUser(user);
      return user;
    });
  }

  Future<void> _persist(AuthTokensModel tokens) async {
    final accessToken = tokens.accessToken;
    if (accessToken == null) return;
    await _storage.saveTokens(
      accessToken: accessToken,
      refreshToken: tokens.refreshToken,
    );
    final user = tokens.user;
    if (user != null) await _preferences.saveUser(user);
  }

  Future<void> _clearLocalSession() async {
    await _storage.clearTokens();
    await _preferences.clearUser();
    await _cache.clear();
  }
}
