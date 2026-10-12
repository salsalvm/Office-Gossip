import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/type_def.dart';
import '../entities/community_post.dart';
import '../repositories/i_community_repository.dart';

class VotePollUseCase implements UseCase<PostPoll, VotePollParams> {
  VotePollUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultFuture<PostPoll> call(VotePollParams params) =>
      repository.votePoll(postId: params.postId, optionId: params.optionId);
}

class VotePollParams {
  const VotePollParams({required this.postId, required this.optionId});

  final String postId;

  /// Null takes the member's vote back.
  final String? optionId;
}
