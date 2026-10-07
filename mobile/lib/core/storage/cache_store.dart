import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/cached.dart';

/// Small JSON cache for offline-first screens (last good API responses).
abstract interface class CacheStore {
  Future<void> write(String key, Object? json);
  Cached<Object?>? read(String key);

  /// Wipes every cached response, e.g. on sign out.
  Future<void> clear();
}

class SharedPrefsCacheStore implements CacheStore {
  SharedPrefsCacheStore(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'officegossip_cache_';

  @override
  Future<void> write(String key, Object? json) => _prefs.setString(
        '$_prefix$key',
        jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          'data': json,
        }),
      );

  @override
  Cached<Object?>? read(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return Cached(map['data'], DateTime.parse(map['savedAt'] as String));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    final keys = _prefs.getKeys().where((key) => key.startsWith(_prefix));
    for (final key in keys.toList()) {
      await _prefs.remove(key);
    }
  }
}
