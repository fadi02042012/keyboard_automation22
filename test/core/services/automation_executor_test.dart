import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_automation/core/services/automation_executor.dart';

void main() {
  group('AutomationExecutor', () {
    test('retries a failed operation and succeeds', () async {
      var attempts = 0;
      final executor = AutomationExecutor(
        isRunning: () => true,
        maxRetries: () => 3,
      );

      await executor.invokeWithRetry(
        action: 'test operation',
        operation: () async {
          attempts++;
          if (attempts < 3) throw StateError('temporary failure');
        },
      );

      expect(attempts, 3);
    });

    test('stops before retry when execution is cancelled', () async {
      var running = true;
      var attempts = 0;
      final executor = AutomationExecutor(
        isRunning: () => running,
        maxRetries: () => 5,
        fastMode: () => true,
      );

      await executor.invokeWithRetry(
        action: 'cancelled operation',
        operation: () async {
          attempts++;
          running = false;
          throw StateError('cancel');
        },
      );

      expect(attempts, 1);
    });

    test('rethrows the last error after retry limit', () async {
      var attempts = 0;
      final executor = AutomationExecutor(
        isRunning: () => true,
        maxRetries: () => 2,
        fastMode: () => true,
      );

      expect(
        () => executor.invokeWithRetry(
          action: 'failing operation',
          operation: () async {
            attempts++;
            throw StateError('permanent failure');
          },
        ),
        throwsA(isA<StateError>()),
      );

      await Future<void>.delayed(Duration.zero);
      expect(attempts, 2);
    });

    test('does not invoke an operation when already stopped', () async {
      var invoked = false;
      final executor = AutomationExecutor(
        isRunning: () => false,
      );

      await executor.invokeWithRetry(
        action: 'stopped operation',
        operation: () async {
          invoked = true;
        },
      );

      expect(invoked, isFalse);
    });

    test('wait returns immediately when stopped', () async {
      final executor = AutomationExecutor(
        isRunning: () => false,
      );

      final stopwatch = Stopwatch()..start();
      await executor.wait(100);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });
  });
}
