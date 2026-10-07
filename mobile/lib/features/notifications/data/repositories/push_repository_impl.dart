import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/logger/app_logger.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/utils/type_def.dart';
import '../../domain/repositories/i_push_repository.dart';
import '../datasources/push_remote_datasource.dart';

class PushRepositoryImpl extends BaseRepository implements IPushRepository {
  PushRepositoryImpl(
    this._remoteDataSource,
    this._logger, {
    required bool firebaseReady,
  }) : _firebaseReady = firebaseReady;

  final IPushRemoteDataSource _remoteDataSource;
  final AppLogger _logger;
  final bool _firebaseReady;
  bool _refreshListenerAdded = false;

  @override
  ResultVoid enableForCurrentUser() {
    return handleRequest(() async {
      if (!_firebaseReady) {
        throw DeviceException(
            'Firebase is not configured for this device yet.');
      }
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
          alert: true, badge: true, sound: true);
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        throw DeviceException(
            'Allow notifications in device settings to enable push.');
      }
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        throw DeviceException('Could not get a notification token. Try again.');
      }
      await _registerToken(token);
      if (!_refreshListenerAdded) {
        _refreshListenerAdded = true;
        messaging.onTokenRefresh.listen((newToken) {
          unawaited(_registerToken(newToken).catchError((Object error) {
            _logger.warning('Push token refresh registration failed: $error');
          }));
        });
      }
      return unit;
    });
  }

  Future<void> _registerToken(String token) {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => throw DeviceException(
          'Push notifications are only configured for iOS and Android.'),
    };
    return _remoteDataSource.registerDevice(
        platform: platform, pushToken: token);
  }
}
