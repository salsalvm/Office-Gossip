import 'package:fpdart/fpdart.dart';

import '../../../usecase/usecase.dart';
import '../../../utils/type_def.dart';
import '../repositories/i_auth_repository.dart';

class RequestPasswordResetUseCase implements UseCase<Unit, String> {
  RequestPasswordResetUseCase(this.repository);

  final IAuthRepository repository;

  /// [params] is the account email.
  @override
  ResultVoid call(String params) =>
      repository.requestPasswordReset(email: params);
}
