import 'package:fpdart/fpdart.dart';

import '../error/exceptions.dart';
import '../error/failure.dart';
import '../utils/type_def.dart';
import 'api_error_message.dart';

/// Converts thrown [AppException]s into `Left(Failure)` for the domain layer.
abstract class BaseRepository {
  ResultFuture<T> handleRequest<T>(Future<T> Function() request) async {
    try {
      return right(await request());
    } on ServerException catch (e) {
      return left(ServerFailure(
        ApiErrorMessage.sanitizeOrDefault(e.message),
        code: e.statusCode,
      ));
    } on NetworkException catch (e) {
      return left(NetworkFailure(ApiErrorMessage.sanitizeOrDefault(e.message)));
    } on AuthException catch (e) {
      return left(AuthFailure(
        ApiErrorMessage.sanitizeOrDefault(e.message),
        code: e.statusCode,
      ));
    } on CacheException catch (e) {
      return left(CacheFailure(ApiErrorMessage.sanitizeOrDefault(e.message)));
    } on DeviceException catch (e) {
      return left(DeviceFailure(e.message));
    } on AppException catch (e) {
      return left(ServerFailure(
        ApiErrorMessage.sanitizeOrDefault(e.message),
        code: e.statusCode,
      ));
    } catch (e) {
      return left(
          UnknownFailure(ApiErrorMessage.sanitizeOrDefault(e.toString())));
    }
  }
}
