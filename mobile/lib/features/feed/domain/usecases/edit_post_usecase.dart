import 'package:fpdart/fpdart.dart';

import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/type_def.dart';
import '../repositories/i_community_repository.dart';

class EditPostUseCase implements UseCase<Unit, EditPostParams> {
  EditPostUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultVoid call(EditPostParams params) =>
      repository.editPost(postId: params.postId, body: params.body);
}

class EditPostParams {
  const EditPostParams({required this.postId, required this.body});

  final String postId;
  final String body;
}
