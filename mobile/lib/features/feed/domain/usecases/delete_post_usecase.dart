import 'package:fpdart/fpdart.dart';

import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/type_def.dart';
import '../repositories/i_community_repository.dart';

class DeletePostUseCase implements UseCase<Unit, String> {
  DeletePostUseCase(this.repository);

  final ICommunityRepository repository;

  /// [params] is the post id.
  @override
  ResultVoid call(String params) => repository.deletePost(params);
}
