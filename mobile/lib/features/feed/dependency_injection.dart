import 'package:dio/dio.dart';

import '../../core/di/injection_container.dart';
import 'data/datasources/community_remote_datasource.dart';
import 'data/repositories/community_repository_impl.dart';
import 'domain/repositories/i_community_repository.dart';
import 'domain/usecases/create_post_usecase.dart';
import 'domain/usecases/load_feed_usecase.dart';
import 'domain/usecases/toggle_post_like_usecase.dart';
import 'presentation/bloc/feed_bloc.dart';
import 'presentation/cubit/community_scope_cubit.dart';

void registerFeedFeature() {
  sl.registerLazySingleton<ICommunityRemoteDataSource>(
    () => CommunityRemoteDataSource(sl<Dio>()),
  );

  sl.registerLazySingleton<ICommunityRepository>(
    () => CommunityRepositoryImpl(sl<ICommunityRemoteDataSource>()),
  );

  sl.registerLazySingleton(() => LoadFeedUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(() => CreatePostUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(
      () => TogglePostLikeUseCase(sl<ICommunityRepository>()));

  sl.registerLazySingleton<CommunityScopeCubit>(CommunityScopeCubit.new);

  sl.registerFactory<FeedBloc>(
    () => FeedBloc(
      loadFeed: sl<LoadFeedUseCase>(),
      togglePostLike: sl<TogglePostLikeUseCase>(),
      createPost: sl<CreatePostUseCase>(),
      initialScope: sl<CommunityScopeCubit>().state,
    ),
  );
}
