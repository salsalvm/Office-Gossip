abstract class Failure {
  const Failure(this.message, {this.code});
  final String message;
  final int? code;

  @override
  String toString() => message;
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.code});
}

class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.code});
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

class DeviceFailure extends Failure {
  const DeviceFailure(super.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}
