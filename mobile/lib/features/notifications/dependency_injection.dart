import 'package:dio/dio.dart';

import '../../core/di/injection_container.dart';
import '../../core/logger/app_logger.dart';
import 'data/datasources/push_remote_datasource.dart';
import 'data/repositories/push_repository_impl.dart';
import 'domain/repositories/i_push_repository.dart';
import 'domain/usecases/enable_push_notifications_usecase.dart';

void registerNotificationsFeature({required bool firebaseReady}) {
  sl.registerLazySingleton<IPushRemoteDataSource>(
    () => PushRemoteDataSource(sl<Dio>()),
  );

  sl.registerLazySingleton<IPushRepository>(
    () => PushRepositoryImpl(
      sl<IPushRemoteDataSource>(),
      sl<AppLogger>(),
      firebaseReady: firebaseReady,
    ),
  );

  sl.registerLazySingleton(
      () => EnablePushNotificationsUseCase(sl<IPushRepository>()));
}
