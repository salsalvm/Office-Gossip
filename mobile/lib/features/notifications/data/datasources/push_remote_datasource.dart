import 'package:dio/dio.dart';

import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/base_remote_data_source.dart';

abstract interface class IPushRemoteDataSource {
  Future<void> registerDevice({
    required String platform,
    required String pushToken,
  });
}

class PushRemoteDataSource extends BaseRemoteDataSource
    implements IPushRemoteDataSource {
  PushRemoteDataSource(this._dio);

  final Dio _dio;

  @override
  Future<void> registerDevice({
    required String platform,
    required String pushToken,
  }) {
    return safeApiCall(() async {
      await _dio.post<dynamic>(
        ApiEndpoints.meDevices,
        data: {'platform': platform, 'pushToken': pushToken},
      );
    });
  }
}
