import 'package:equatable/equatable.dart';

/// A deleted (deactivated) account found while signing in. Self-deleted
/// accounts can be restored until [purgeAfter]; admin deactivations cannot.
class DeactivatedAccount extends Equatable {
  const DeactivatedAccount({
    required this.message,
    required this.canRestore,
    this.email,
    this.deactivatedAt,
    this.purgeAfter,
  });

  final String message;
  final bool canRestore;
  final String? email;
  final DateTime? deactivatedAt;
  final DateTime? purgeAfter;

  /// Whole days left before permanent deletion, rounded up.
  int? get daysLeft {
    final purge = purgeAfter;
    if (purge == null) return null;
    final hours = purge.difference(DateTime.now()).inHours;
    return hours <= 0 ? 0 : (hours / 24).ceil();
  }

  @override
  List<Object?> get props =>
      [message, canRestore, email, deactivatedAt, purgeAfter];
}

/// Result of deleting the signed-in account.
class AccountDeletion extends Equatable {
  const AccountDeletion({this.purgeAfter, required this.graceDays});
  final DateTime? purgeAfter;
  final int graceDays;

  @override
  List<Object?> get props => [purgeAfter, graceDays];
}
