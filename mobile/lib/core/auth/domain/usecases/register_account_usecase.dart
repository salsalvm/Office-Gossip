import '../../../usecase/usecase.dart';
import '../../../utils/type_def.dart';
import '../entities/session.dart';
import '../repositories/i_auth_repository.dart';

class RegisterAccountUseCase
    implements UseCase<RegistrationResult, RegisterAccountParams> {
  RegisterAccountUseCase(this.repository);

  final IAuthRepository repository;

  @override
  ResultFuture<RegistrationResult> call(RegisterAccountParams params) =>
      repository.register(
        name: params.name,
        email: params.email,
        password: params.password,
        companyName: params.companyName,
      );
}

class RegisterAccountParams {
  const RegisterAccountParams({
    required this.name,
    required this.email,
    required this.password,
    required this.companyName,
  });

  final String name;
  final String email;
  final String password;
  final String companyName;
}
