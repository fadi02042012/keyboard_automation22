import 'dart:developer' as developer;

/// Centralized application logging for diagnostics without coupling the UI to
/// a concrete logging backend.
final class AppLogger {
  AppLogger._();

  static bool enabled = true;
  static bool debugEnabled = false;

  static void debug(String message, {String name = 'keyboard_automation'}) {
    if (!enabled || !debugEnabled) return;
    developer.log(message, name: '$name.debug', level: 500);
  }

  static void info(String message, {String name = 'keyboard_automation'}) {
    if (!enabled) return;
    developer.log(message, name: '$name.info', level: 800);
  }

  static void warning(String message, {Object? error, StackTrace? stackTrace, String name = 'keyboard_automation'}) {
    if (!enabled) return;
    developer.log(
      message,
      name: '$name.warning',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String name = 'keyboard_automation',
  }) {
    if (!enabled) return;
    developer.log(
      message,
      name: '$name.error',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
