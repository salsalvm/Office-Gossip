import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/cached.dart';
import '../../../../core/utils/type_def.dart';
import '../../../feed/domain/entities/community_member.dart';
import '../../../feed/domain/repositories/i_community_repository.dart';

class LoadPeopleUseCase implements UseCase<List<CommunityMember>, NoParams> {
  LoadPeopleUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultFuture<List<CommunityMember>> call(NoParams params) =>
      repository.loadPeople();

  Cached<List<CommunityMember>>? cached() => repository.cachedPeople();
}
