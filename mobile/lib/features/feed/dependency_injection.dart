import 'package:dio/dio.dart';

import '../../core/di/injection_container.dart';
import '../../core/storage/cache_store.dart';
import 'data/datasources/community_local_datasource.dart';
import 'data/datasources/community_remote_datasource.dart';
import 'data/repositories/community_repository_impl.dart';
import 'domain/repositories/i_community_repository.dart';
import 'domain/usecases/archive_post_usecase.dart';
import 'domain/usecases/create_post_usecase.dart';
import 'domain/usecases/delete_post_usecase.dart';
import 'domain/usecases/edit_post_usecase.dart';
import 'domain/usecases/load_announcements_usecase.dart';
import 'domain/usecases/load_feed_usecase.dart';
import 'domain/usecases/report_post_usecase.dart';
import 'domain/usecases/toggle_post_like_usecase.dart';
import 'presentation/bloc/feed_bloc.dart';
import 'presentation/cubit/community_scope_cubit.dart';

void registerFeedFeature() {
  sl.registerLazySingleton<ICommunityRemoteDataSource>(
    () => CommunityRemoteDataSource(sl<Dio>()),
  );

  sl.registerLazySingleton<ICommunityLocalDataSource>(
    () => CommunityLocalDataSource(sl<CacheStore>()),
  );

  sl.registerLazySingleton<ICommunityRepository>(
    () => CommunityRepositoryImpl(
      sl<ICommunityRemoteDataSource>(),
      sl<ICommunityLocalDataSource>(),
    ),
  );

  sl.registerLazySingleton(() => LoadFeedUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(() => CreatePostUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(
      () => LoadAnnouncementsUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(
      () => TogglePostLikeUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(() => EditPostUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(() => DeletePostUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(() => ReportPostUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(
      () => ArchivePostUseCase(sl<ICommunityRepository>()));

  sl.registerLazySingleton<CommunityScopeCubit>(CommunityScopeCubit.new);

  sl.registerFactory<FeedBloc>(
    () => FeedBloc(
      loadFeed: sl<LoadFeedUseCase>(),
      loadAnnouncements: sl<LoadAnnouncementsUseCase>(),
      togglePostLike: sl<TogglePostLikeUseCase>(),
      createPost: sl<CreatePostUseCase>(),
      editPost: sl<EditPostUseCase>(),
      deletePost: sl<DeletePostUseCase>(),
      reportPost: sl<ReportPostUseCase>(),
      archivePost: sl<ArchivePostUseCase>(),
      initialScope: sl<CommunityScopeCubit>().state,
    ),
  );
}
