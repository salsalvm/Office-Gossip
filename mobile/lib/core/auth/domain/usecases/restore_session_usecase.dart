import '../../../usecase/usecase.dart';
import '../../../utils/type_def.dart';
import '../entities/session.dart';
import '../repositories/i_auth_repository.dart';

class RestoreSessionUseCase implements UseCase<Session?, NoParams> {
  RestoreSessionUseCase(this.repository);

  final IAuthRepository repository;

  @override
  ResultFuture<Session?> call(NoParams params) => repository.restoreSession();
}
