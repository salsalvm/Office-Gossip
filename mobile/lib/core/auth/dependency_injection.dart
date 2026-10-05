import '../storage/cache_store.dart';
import 'package:dio/dio.dart';

import '../di/injection_container.dart';
import '../storage/app_preferences_service.dart';
import '../storage/secure_storage_service.dart';
import 'data/datasources/auth_remote_datasource.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'domain/repositories/i_auth_repository.dart';
import 'domain/usecases/refresh_user_usecase.dart';
import 'domain/usecases/register_account_usecase.dart';
import 'domain/usecases/request_password_reset_usecase.dart';
import 'domain/usecases/restore_session_usecase.dart';
import 'domain/usecases/sign_in_usecase.dart';
import 'domain/usecases/sign_out_usecase.dart';
import 'domain/usecases/update_profile_usecase.dart';
import 'presentation/bloc/auth_bloc.dart';

void registerAuthFeature() {
  sl.registerLazySingleton<IAuthRemoteDataSource>(
    () => AuthRemoteDataSource(sl<Dio>()),
  );

  sl.registerLazySingleton<IAuthRepository>(
    () => AuthRepositoryImpl(
      sl<IAuthRemoteDataSource>(),
      sl<SecureStorageService>(),
      sl<AppPreferencesService>(),
      sl<CacheStore>(),
    ),
  );

  sl.registerLazySingleton(() => RestoreSessionUseCase(sl<IAuthRepository>()));
  sl.registerLazySingleton(() => SignInUseCase(sl<IAuthRepository>()));
  sl.registerLazySingleton(() => RegisterAccountUseCase(sl<IAuthRepository>()));
  sl.registerLazySingleton(
      () => RequestPasswordResetUseCase(sl<IAuthRepository>()));
  sl.registerLazySingleton(() => SignOutUseCase(sl<IAuthRepository>()));
  sl.registerLazySingleton(() => RefreshUserUseCase(sl<IAuthRepository>()));
  sl.registerLazySingleton(() => UpdateProfileUseCase(sl<IAuthRepository>()));

  // App-wide: the router and every auth screen share one instance.
  sl.registerLazySingleton<AuthBloc>(
    () => AuthBloc(
      restoreSession: sl<RestoreSessionUseCase>(),
      signIn: sl<SignInUseCase>(),
      registerAccount: sl<RegisterAccountUseCase>(),
      signOut: sl<SignOutUseCase>(),
      requestPasswordReset: sl<RequestPasswordResetUseCase>(),
    ),
  );
}
