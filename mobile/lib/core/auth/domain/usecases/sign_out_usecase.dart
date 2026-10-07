import 'package:fpdart/fpdart.dart';

import '../../../usecase/usecase.dart';
import '../../../utils/type_def.dart';
import '../repositories/i_auth_repository.dart';

class SignOutUseCase implements UseCase<Unit, NoParams> {
  SignOutUseCase(this.repository);

  final IAuthRepository repository;

  @override
  ResultVoid call(NoParams params) => repository.signOut();
}
