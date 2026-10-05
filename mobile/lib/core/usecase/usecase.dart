import '../utils/type_def.dart';

abstract interface class UseCase<SuccessType, Params> {
  ResultFuture<SuccessType> call(Params params);
}

class NoParams {
  const NoParams();
}
