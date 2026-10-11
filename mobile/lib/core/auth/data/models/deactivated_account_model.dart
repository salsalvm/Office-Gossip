import '../../../network/api_error_message.dart';
import '../../domain/entities/deactivated_account.dart';

class DeactivatedAccountModel extends DeactivatedAccount {
  const DeactivatedAccountModel({
    required super.message,
    required super.canRestore,
    super.email,
    super.deactivatedAt,
    super.purgeAfter,
  });

  static const String errorCode = 'ACCOUNT_DEACTIVATED';

  /// Reads a 403 sign-in error body: `{ message, data: { code, canRestore, ... } }`.
  /// Returns null for any other error.
  static DeactivatedAccountModel? tryParse(int? statusCode, Object? body) {
    if (statusCode != 403 || body is! Map) return null;
    final data = body['data'];
    if (data is! Map || data['code'] != errorCode) return null;
    return DeactivatedAccountModel(
      message: ApiErrorMessage.fromResponseBody(body) ??
          'This account is scheduled for deletion.',
      canRestore: data['canRestore'] == true,
      email: data['email'] as String?,
      deactivatedAt: DateTime.tryParse(data['deactivatedAt'] as String? ?? ''),
      purgeAfter: DateTime.tryParse(data['purgeAfter'] as String? ?? ''),
    );
  }
}
