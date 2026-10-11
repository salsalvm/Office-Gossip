import 'package:dio/dio.dart';

import '../../../error/exceptions.dart';
import '../../../network/api_endpoints.dart';
import '../../../network/base_remote_data_source.dart';
import '../../domain/entities/deactivated_account.dart';
import '../models/app_user_model.dart';
import '../models/auth_tokens_model.dart';
import '../models/deactivated_account_model.dart';

abstract interface class IAuthRemoteDataSource {
  Future<AuthTokensModel> login({
    required String email,
    required String password,
  });

  Future<AuthTokensModel> register({
    required String name,
    required String email,
    required String password,
    String? companyId,
    String? companyName,
    String? companyWebsite,
    String? verificationToken,
  });

  Future<void> requestPasswordReset({required String email});

  Future<void> logout();

  Future<AppUserModel> getCurrentUser();

  Future<void> updateProfile({
    required String displayName,
    String? roleTitle,
    String? bio,
  });

  Future<AppUserModel> chooseCompany({
    String? companyId,
    String? companyName,
    String? companyWebsite,
  });

  /// Throws [AccountDeactivatedException] when the account can't be restored.
  Future<AuthTokensModel> restoreAccount({
    required String email,
    required String password,
  });

  Future<AccountDeletion> deleteAccount({
    required String password,
    String? reason,
  });

  Future<int> accountGraceDays();
}

class AuthRemoteDataSource extends BaseRemoteDataSource
    implements IAuthRemoteDataSource {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  @override
  Future<AuthTokensModel> login({
    required String email,
    required String password,
  }) =>
      _signIn(ApiEndpoints.login, email: email, password: password);

  @override
  Future<AuthTokensModel> restoreAccount({
    required String email,
    required String password,
  }) =>
      _signIn(ApiEndpoints.restoreAccount, email: email, password: password);

  Future<AuthTokensModel> _signIn(
    String endpoint, {
    required String email,
    required String password,
  }) {
    return safeApiCall(() async {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          endpoint,
          data: {'email': email, 'password': password},
        );
        return AuthTokensModel.fromJson(response.data!);
      } on DioException catch (e) {
        final account = DeactivatedAccountModel.tryParse(
            e.response?.statusCode, e.response?.data);
        if (account != null) throw AccountDeactivatedException(account);
        rethrow;
      }
    });
  }

  @override
  Future<AccountDeletion> deleteAccount({
    required String password,
    String? reason,
  }) {
    return safeApiCall(() async {
      final response = await _dio.delete<Map<String, dynamic>>(
        ApiEndpoints.meAccount,
        data: {
          'password': password,
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason,
        },
      );
      final data = response.data ?? const <String, dynamic>{};
      return AccountDeletion(
        purgeAfter: DateTime.tryParse(data['purgeAfter'] as String? ?? ''),
        graceDays: (data['graceDays'] as num?)?.toInt() ?? 30,
      );
    });
  }

  @override
  Future<int> accountGraceDays() {
    return safeApiCall(() async {
      final response =
          await _dio.get<Map<String, dynamic>>(ApiEndpoints.accountPolicy);
      return (response.data?['graceDays'] as num?)?.toInt() ?? 30;
    });
  }

  @override
  Future<AuthTokensModel> register({
    required String name,
    required String email,
    required String password,
    String? companyId,
    String? companyName,
    String? companyWebsite,
    String? verificationToken,
  }) {
    return safeApiCall(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.register,
        data: {
          'name': name,
          'email': email,
          'password': password,
          if (companyId != null) 'companyId': companyId,
          if (companyName != null) 'companyName': companyName,
          if (companyWebsite != null) 'companyWebsite': companyWebsite,
          if (verificationToken != null) 'verificationToken': verificationToken,
        },
      );
      return AuthTokensModel.fromJson(response.data!);
    });
  }

  @override
  Future<void> requestPasswordReset({required String email}) {
    return safeApiCall(() async {
      await _dio.post<dynamic>(
        ApiEndpoints.forgotPassword,
        data: {'email': email},
      );
    });
  }

  @override
  Future<void> logout() {
    return safeApiCall(() async {
      await _dio.post<dynamic>(ApiEndpoints.logout);
    });
  }

  @override
  Future<AppUserModel> getCurrentUser() {
    return safeApiCall(() async {
      final response = await _dio.get<Map<String, dynamic>>(ApiEndpoints.me);
      return AppUserModel.fromJson(
          Map<String, dynamic>.from(response.data!['user'] as Map));
    });
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    String? roleTitle,
    String? bio,
  }) {
    return safeApiCall(() async {
      await _dio.patch<dynamic>(
        ApiEndpoints.meProfile,
        data: {'displayName': displayName, 'roleTitle': roleTitle, 'bio': bio},
      );
    });
  }

  @override
  Future<AppUserModel> chooseCompany({
    String? companyId,
    String? companyName,
    String? companyWebsite,
  }) {
    return safeApiCall(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.meCompany,
        data: companyId != null
            ? {'companyId': companyId}
            : {
                'companyName': companyName,
                if (companyWebsite != null) 'companyWebsite': companyWebsite,
              },
      );
      return AppUserModel.fromJson(
          Map<String, dynamic>.from(response.data!['user'] as Map));
    });
  }
}
