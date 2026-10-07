import 'package:dio/dio.dart';

import '../../../network/api_endpoints.dart';
import '../../../network/base_remote_data_source.dart';
import '../models/app_user_model.dart';
import '../models/auth_tokens_model.dart';

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
}

class AuthRemoteDataSource extends BaseRemoteDataSource
    implements IAuthRemoteDataSource {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  @override
  Future<AuthTokensModel> login({
    required String email,
    required String password,
  }) {
    return safeApiCall(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.login,
        data: {'email': email, 'password': password},
      );
      return AuthTokensModel.fromJson(response.data!);
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
}
