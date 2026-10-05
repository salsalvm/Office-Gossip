import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/cached.dart';
import '../../../../core/utils/type_def.dart';
import '../entities/community_post.dart';
import '../entities/community_scope.dart';
import '../repositories/i_community_repository.dart';

class LoadFeedUseCase implements UseCase<List<CommunityPost>, CommunityScope> {
  LoadFeedUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultFuture<List<CommunityPost>> call(CommunityScope params) =>
      repository.loadFeed(params);

  /// Last synced copy, shown instantly and when the network is unavailable.
  Cached<List<CommunityPost>>? cached(CommunityScope scope) =>
      repository.cachedFeed(scope);
}
