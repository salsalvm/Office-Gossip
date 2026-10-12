import 'package:dio/dio.dart';

import '../../core/di/injection_container.dart';
import '../../core/storage/cache_store.dart';
import 'data/datasources/community_local_datasource.dart';
import 'data/datasources/community_remote_datasource.dart';
import 'data/repositories/community_repository_impl.dart';
import 'domain/repositories/i_community_repository.dart';
import 'domain/usecases/archive_post_usecase.dart';
import 'domain/usecases/block_usecases.dart';
import 'domain/usecases/saved_posts_usecases.dart';
import 'domain/usecases/vote_poll_usecase.dart';
import 'domain/usecases/create_post_usecase.dart';
import 'domain/usecases/delete_post_usecase.dart';
import 'domain/usecases/edit_post_usecase.dart';
import 'domain/usecases/load_announcements_usecase.dart';
import 'domain/usecases/load_feed_usecase.dart';
import 'domain/usecases/report_post_usecase.dart';
import 'domain/usecases/post_reaction_usecases.dart';
import 'presentation/bloc/feed_bloc.dart';
import 'presentation/cubit/blocked_members_cubit.dart';
import 'presentation/cubit/community_scope_cubit.dart';
import 'presentation/cubit/saved_posts_cubit.dart';

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
      () => SetPostReactionUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(() => LoadTopicsUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(() => EditPostUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(() => DeletePostUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(() => ReportPostUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(
      () => ArchivePostUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(() => VotePollUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(
      () => SetPostSavedUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(
      () => LoadSavedPostsUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(
      () => BlockAuthorUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(
      () => SetMemberBlockUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(() => LoadBlocksUseCase(sl<ICommunityRepository>()));
  sl.registerLazySingleton(
      () => RemoveBlockUseCase(sl<ICommunityRepository>()));

  sl.registerLazySingleton<CommunityScopeCubit>(CommunityScopeCubit.new);
  sl.registerFactory(() => SavedPostsCubit(sl<LoadSavedPostsUseCase>(),
      sl<SetPostSavedUseCase>(), sl<VotePollUseCase>()));
  sl.registerFactory(() =>
      BlockedMembersCubit(sl<LoadBlocksUseCase>(), sl<RemoveBlockUseCase>()));

  // Param: `true` for the Trending list.
  sl.registerFactoryParam<FeedBloc, bool, void>(
    (trending, _) => FeedBloc(
      loadFeed: sl<LoadFeedUseCase>(),
      loadAnnouncements: sl<LoadAnnouncementsUseCase>(),
      setReaction: sl<SetPostReactionUseCase>(),
      loadTopics: sl<LoadTopicsUseCase>(),
      createPost: sl<CreatePostUseCase>(),
      editPost: sl<EditPostUseCase>(),
      deletePost: sl<DeletePostUseCase>(),
      reportPost: sl<ReportPostUseCase>(),
      archivePost: sl<ArchivePostUseCase>(),
      votePoll: sl<VotePollUseCase>(),
      setPostSaved: sl<SetPostSavedUseCase>(),
      blockAuthor: sl<BlockAuthorUseCase>(),
      initialScope: sl<CommunityScopeCubit>().state,
      trending: trending,
    ),
  );
}
