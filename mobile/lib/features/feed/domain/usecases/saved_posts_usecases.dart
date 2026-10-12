import 'package:fpdart/fpdart.dart';

import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/type_def.dart';
import '../entities/community_post.dart';
import '../repositories/i_community_repository.dart';

class SetPostSavedUseCase implements UseCase<Unit, SetPostSavedParams> {
  SetPostSavedUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultVoid call(SetPostSavedParams params) =>
      repository.setSaved(postId: params.postId, saved: params.saved);
}

class SetPostSavedParams {
  const SetPostSavedParams({required this.postId, required this.saved});

  final String postId;
  final bool saved;
}

class LoadSavedPostsUseCase implements UseCase<List<CommunityPost>, NoParams> {
  LoadSavedPostsUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultFuture<List<CommunityPost>> call(NoParams params) =>
      repository.loadSaved();
}
