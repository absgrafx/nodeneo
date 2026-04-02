import 'package:flutter/foundation.dart';

import 'bridge.dart';

/// Unified application logger: writes to both Flutter console (debugPrint) and
/// nodeneo.log (via the Go FFI bridge).
///
/// Usage:  `AppLogger.info('Wallet restored');`
///
/// Falls back gracefully to debugPrint-only if the bridge isn't initialized yet.
class AppLogger {
  AppLogger._();

  static void debug(String message) => _log('debug', message);
  static void info(String message)  => _log('info', message);
  static void warn(String message)  => _log('warn', message);
  static void error(String message) => _log('error', message);

  static void _log(String level, String message) {
    debugPrint('[${level.toUpperCase()}] $message');
    try {
      final bridge = GoBridge();
      if (bridge.initialized) {
        bridge.appLog(level, message);
      }
    } catch (_) {
      // Bridge not available yet — console-only is fine.
    }
  }
}
