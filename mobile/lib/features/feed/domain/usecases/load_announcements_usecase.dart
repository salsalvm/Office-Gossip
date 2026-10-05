import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/cached.dart';
import '../../../../core/utils/type_def.dart';
import '../entities/announcement.dart';
import '../repositories/i_community_repository.dart';

class LoadAnnouncementsUseCase
    implements UseCase<List<Announcement>, NoParams> {
  LoadAnnouncementsUseCase(this.repository);

  final ICommunityRepository repository;

  @override
  ResultFuture<List<Announcement>> call(NoParams params) =>
      repository.loadAnnouncements();

  Cached<List<Announcement>>? cached() => repository.cachedAnnouncements();
}
