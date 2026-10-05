import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/storage_keys.dart';
import 'secure_storage_service.dart';

class SecureStorageServiceImpl implements SecureStorageService {
  SecureStorageServiceImpl(this._storage);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessToken() =>
      _storage.read(key: StorageKeys.accessToken);

  @override
  Future<String?> readRefreshToken() =>
      _storage.read(key: StorageKeys.refreshToken);

  @override
  Future<void> saveTokens(
      {required String accessToken, String? refreshToken}) async {
    await _storage.write(key: StorageKeys.accessToken, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: StorageKeys.refreshToken, value: refreshToken);
    }
  }

  @override
  Future<void> clearTokens() async {
    await _storage.delete(key: StorageKeys.accessToken);
    await _storage.delete(key: StorageKeys.refreshToken);
  }
}
