import 'package:fpdart/fpdart.dart';

import '../../../../core/usecase/usecase.dart';
import '../../../../core/utils/type_def.dart';
import '../repositories/i_push_repository.dart';

class EnablePushNotificationsUseCase implements UseCase<Unit, NoParams> {
  EnablePushNotificationsUseCase(this.repository);

  final IPushRepository repository;

  @override
  ResultVoid call(NoParams params) => repository.enableForCurrentUser();
}
