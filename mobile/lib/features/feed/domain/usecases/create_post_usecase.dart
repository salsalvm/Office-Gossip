import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/type_def.dart';
import '../repositories/i_community_repository.dart';

class CreatePostUseCase implements UseCase<bool, CreatePostParams> {
  CreatePostUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultFuture<bool> call(CreatePostParams params) =>
      repository.createPost(body: params.body, anonymous: params.anonymous);
}

class CreatePostParams {
  const CreatePostParams({required this.body, required this.anonymous});

  final String body;
  final bool anonymous;
}
