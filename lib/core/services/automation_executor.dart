import 'dart:async';

import '../../core/app_logger.dart';

typedef AutomationOperation = Future<void> Function();

/// Reusable execution primitives shared by the desktop automation runner.
///
/// Keeping retry/backoff/cancellation here prevents the UI state object from
/// owning low-level execution policy and makes the behavior unit-testable.
class AutomationExecutor {
  AutomationExecutor({
    required this.isRunning,
    int Function()? maxRetries,
    bool Function()? fastMode,
  })  : _maxRetries = maxRetries ?? (() => 3),
        _fastMode = fastMode ?? (() => false);

  final int Function() _maxRetries;
  final bool Function() _fastMode;

  final bool Function() isRunning;
  Future<void> wait(int milliseconds) async {
    if (milliseconds <= 0 || !isRunning()) return;
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
  }

  Future<void> invokeWithRetry({
    required String action,
    required AutomationOperation operation,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final configuredRetries = _maxRetries();
    final attempts = configuredRetries < 1 ? 1 : configuredRetries;
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt < attempts; attempt++) {
      if (!isRunning()) return;

      try {
        await operation().timeout(timeout);
        return;
      } on TimeoutException catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        AppLogger.warning(
          '$action timed out on attempt ${attempt + 1}/$attempts.',
          error: error,
          stackTrace: stackTrace,
          name: 'automation',
        );
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        AppLogger.warning(
          '$action attempt ${attempt + 1}/$attempts failed.',
          error: error,
          stackTrace: stackTrace,
          name: 'automation',
        );
      }

      if (!isRunning() || attempt + 1 >= attempts) break;
      final backoffMs = _fastMode() ? 20 : (50 * (attempt + 1)).clamp(50, 250);
      await wait(backoffMs);
    }

    if (lastError != null) {
      Error.throwWithStackTrace(lastError!, lastStackTrace ?? StackTrace.current);
    }
    throw StateError('$action failed');
  }
}
