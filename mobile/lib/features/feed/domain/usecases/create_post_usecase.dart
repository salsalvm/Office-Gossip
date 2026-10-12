import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/type_def.dart';
import '../repositories/i_community_repository.dart';

class CreatePostUseCase implements UseCase<bool, CreatePostParams> {
  CreatePostUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultFuture<bool> call(CreatePostParams params) => repository.createPost(
      body: params.body, anonymous: params.anonymous, poll: params.poll);
}

class CreatePostParams {
  const CreatePostParams(
      {required this.body, required this.anonymous, this.poll});

  final String body;
  final bool anonymous;

  /// 2–4 poll option labels, or null for a plain post.
  final List<String>? poll;
}
