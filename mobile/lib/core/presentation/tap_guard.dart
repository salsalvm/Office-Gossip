import 'package:flutter/foundation.dart';

/// Drops taps that land within [window] of the previous accepted tap anywhere
/// in the app, so a double tap can't submit twice or hit the screen revealed
/// after a sheet closes.
abstract final class TapGuard {
  static const Duration window = Duration(milliseconds: 500);
  static DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _dispatching = false;

  /// Returns the same nullability it receives, so it fits both optional and
  /// required callback parameters. Wrapping an already-guarded callback is
  /// safe: the inner guard passes the accepted tap through.
  static T wrap<T extends VoidCallback?>(T onTap) {
    if (onTap == null) return onTap;
    final callback = onTap as VoidCallback;
    void guarded() {
      if (_dispatching) return callback();
      final now = DateTime.now();
      if (now.difference(_lastTap) < window) return;
      _lastTap = now;
      _dispatching = true;
      try {
        callback();
      } finally {
        _dispatching = false;
      }
    }

    return guarded as T;
  }
}
