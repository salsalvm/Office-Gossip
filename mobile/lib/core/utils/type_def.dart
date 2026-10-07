import 'package:fpdart/fpdart.dart';

import '../error/failure.dart';

typedef ResultFuture<T> = Future<Either<Failure, T>>;
typedef ResultVoid = ResultFuture<Unit>;
