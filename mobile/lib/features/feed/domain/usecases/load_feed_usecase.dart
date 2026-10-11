import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/cached.dart';
import '../../../../core/utils/type_def.dart';
import '../entities/community_post.dart';
import '../entities/community_scope.dart';
import '../repositories/i_community_repository.dart';

class LoadFeedUseCase implements UseCase<List<CommunityPost>, CommunityScope> {
  LoadFeedUseCase(this.repository);

  final ICommunityRepository repository;

  static const pageSize = 20;

  /// Trending is a short top list, loaded in one request.
  static const trendingLimit = 10;

  /// First page of the feed.
  @override
  ResultFuture<List<CommunityPost>> call(CommunityScope params) =>
      repository.loadFeed(params, limit: pageSize);

  /// The page of posts older than [before].
  ResultFuture<List<CommunityPost>> olderThan(
          CommunityScope scope, String before) =>
      repository.loadFeed(scope, before: before, limit: pageSize);

  /// The top [trendingLimit] most-interacted recent posts.
  ResultFuture<List<CommunityPost>> trending(CommunityScope scope) =>
      repository.loadFeed(scope, trending: true, limit: trendingLimit);

  /// Last synced copy, shown instantly and when the network is unavailable.
  Cached<List<CommunityPost>>? cached(CommunityScope scope) =>
      repository.cachedFeed(scope);
}
