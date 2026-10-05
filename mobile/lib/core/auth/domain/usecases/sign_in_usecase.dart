import '../../../usecase/usecase.dart';
import '../../../utils/type_def.dart';
import '../entities/session.dart';
import '../repositories/i_auth_repository.dart';

class SignInUseCase implements UseCase<Session, SignInParams> {
  SignInUseCase(this.repository);

  final IAuthRepository repository;

  @override
  ResultFuture<Session> call(SignInParams params) =>
      repository.signIn(email: params.email, password: params.password);
}

class SignInParams {
  const SignInParams({required this.email, required this.password});

  final String email;
  final String password;
}
