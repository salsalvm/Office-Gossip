import '../../../usecase/usecase.dart';
import '../../../utils/type_def.dart';
import '../entities/app_user.dart';
import '../repositories/i_auth_repository.dart';

class RefreshUserUseCase implements UseCase<AppUser, NoParams> {
  RefreshUserUseCase(this.repository);

  final IAuthRepository repository;

  @override
  ResultFuture<AppUser> call(NoParams params) => repository.refreshUser();
}
