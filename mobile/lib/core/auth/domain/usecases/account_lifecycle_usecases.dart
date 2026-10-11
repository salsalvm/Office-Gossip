import '../../../usecase/usecase.dart';
import '../../../utils/type_def.dart';
import '../entities/deactivated_account.dart';
import '../entities/session.dart';
import '../repositories/i_auth_repository.dart';
import 'sign_in_usecase.dart';

class RestoreAccountUseCase implements UseCase<Session, SignInParams> {
  RestoreAccountUseCase(this.repository);

  final IAuthRepository repository;

  @override
  ResultFuture<Session> call(SignInParams params) =>
      repository.restoreAccount(email: params.email, password: params.password);
}

class DeleteAccountUseCase
    implements UseCase<AccountDeletion, DeleteAccountParams> {
  DeleteAccountUseCase(this.repository);

  final IAuthRepository repository;

  @override
  ResultFuture<AccountDeletion> call(DeleteAccountParams params) => repository
      .deleteAccount(password: params.password, reason: params.reason);
}

class DeleteAccountParams {
  const DeleteAccountParams({required this.password, this.reason});

  final String password;
  final String? reason;
}

class GetAccountGraceDaysUseCase implements UseCase<int, NoParams> {
  GetAccountGraceDaysUseCase(this.repository);

  final IAuthRepository repository;

  @override
  ResultFuture<int> call(NoParams params) => repository.accountGraceDays();
}
