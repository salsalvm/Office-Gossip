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
        companyId: params.companyId,
        companyName: params.companyName,
        companyWebsite: params.companyWebsite,
        verificationToken: params.verificationToken,
      );
}

/// Pass either [companyId] (a listed company) or [companyName] (a request for
/// a new one, optionally with [companyWebsite]).
class RegisterAccountParams {
  const RegisterAccountParams({
    required this.name,
    required this.email,
    required this.password,
    this.companyId,
    this.companyName,
    this.companyWebsite,
    this.verificationToken,
  });

  final String name;
  final String email;
  final String password;
  final String? companyId;
  final String? companyName;
  final String? companyWebsite;
  final String? verificationToken;
}
