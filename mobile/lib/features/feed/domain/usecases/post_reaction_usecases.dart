import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/type_def.dart';
import '../entities/community_scope.dart';
import '../entities/post_reaction.dart';
import '../entities/topic.dart';
import '../repositories/i_community_repository.dart';

class SetPostReactionUseCase
    implements UseCase<ReactionState, SetPostReactionParams> {
  SetPostReactionUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultFuture<ReactionState> call(SetPostReactionParams params) =>
      repository.setReaction(postId: params.postId, reaction: params.reaction);
}

class SetPostReactionParams {
  const SetPostReactionParams({required this.postId, required this.reaction});

  final String postId;

  /// Null removes the member's reaction.
  final PostReaction? reaction;
}

class LoadTopicsUseCase implements UseCase<List<Topic>, CommunityScope> {
  LoadTopicsUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultFuture<List<Topic>> call(CommunityScope params) =>
      repository.loadTopics(params);
}
