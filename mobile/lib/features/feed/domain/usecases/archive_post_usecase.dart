import 'package:fpdart/fpdart.dart';

import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/type_def.dart';
import '../repositories/i_community_repository.dart';

class ArchivePostUseCase implements UseCase<Unit, ArchivePostParams> {
  ArchivePostUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultVoid call(ArchivePostParams params) =>
      repository.archivePost(postId: params.postId, archived: params.archived);
}

class ArchivePostParams {
  const ArchivePostParams({required this.postId, required this.archived});

  final String postId;
  final bool archived;
}
