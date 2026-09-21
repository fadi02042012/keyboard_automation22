import 'package:flutter/services.dart';

/// Thin, testable boundary around the Windows MethodChannels.
///
/// Channel names and method names intentionally remain unchanged to preserve
/// compatibility with the existing Windows runner.
class NativeAutomationService {
  NativeAutomationService({
    MethodChannel? automationChannel,
    MethodChannel? windowsChannel,
  })  : automationChannel =
            automationChannel ?? const MethodChannel(_automationChannelName),
        windowsChannel =
            windowsChannel ?? const MethodChannel(_windowsChannelName);

  static const String _automationChannelName =
      'keyboard_automation/keyboard';
  static const String _windowsChannelName = 'keyboard_automation/windows';

  final MethodChannel automationChannel;
  final MethodChannel windowsChannel;

  Future<T?> invokeAutomation<T>(
    String method, [
    dynamic arguments,
  ]) {
    return automationChannel.invokeMethod<T>(method, arguments);
  }

  Future<T?> invokeWindows<T>(
    String method, [
    dynamic arguments,
  ]) {
    return windowsChannel.invokeMethod<T>(method, arguments);
  }

  /// Returns the current screen cursor position.
  ///
  /// An empty map is deliberately sent even though the native method does not
  /// need values. This keeps the call compatible with runners that validate
  /// every invocation as a map of arguments.
  Future<Map<String, int>?> getMousePosition() async {
    final raw = await invokeAutomation<dynamic>(
      'get_mouse_position',
      <String, dynamic>{},
    );
    if (raw is! Map) return null;

    int? readCoordinate(Object? value) {
      if (value is int) return value;
      if (value is num && value.isFinite) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    final x = readCoordinate(raw['x']);
    final y = readCoordinate(raw['y']);
    if (x == null || y == null) return null;
    return <String, int>{'x': x, 'y': y};
  }

  Future<List<Map<String, dynamic>>> inspectUiElements({
    required String windowTitle,
    int maxDepth = 4,
    int maxElements = 200,
  }) async {
    final raw = await invokeAutomation<dynamic>('ui_inspect_elements', {
      'windowTitle': windowTitle,
      'maxDepth': maxDepth,
      'maxElements': maxElements,
    });
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> executeSemanticCommand({
    required String windowTitle,
    String windowAlias = '',
    required String command,
    required Map<String, dynamic> arguments,
    int waitTimeoutMs = 5000,
  }) async {
    if (command == 'wait_for_element') {
      await waitForUiElement(
        windowTitle: windowTitle,
        windowAlias: windowAlias,
        arguments: arguments,
        timeoutMs: waitTimeoutMs,
      );
      return;
    }
    await invokeAutomation<void>('ui_execute_command', {
      'windowTitle': windowTitle,
      if (windowAlias.trim().isNotEmpty) 'windowAlias': windowAlias.trim(),
      'command': command,
      ...arguments,
    });
  }

  Future<void> waitForUiElement({
    required String windowTitle,
    String windowAlias = '',
    required Map<String, dynamic> arguments,
    int timeoutMs = 5000,
  }) async {
    // windowAlias is the logical identity; native activation is handled by
    // the caller before UI Automation inspection.
    final deadline = DateTime.now().add(
      Duration(milliseconds: timeoutMs.clamp(100, 30000).toInt()),
    );
    while (DateTime.now().isBefore(deadline)) {
      final elements = await inspectUiElements(
        windowTitle: windowTitle,
        maxDepth: 8,
        maxElements: 500,
      );
      final found = elements.any((element) {
        bool matches(String key) {
          final expected = arguments[key]?.toString().trim() ?? '';
          return expected.isEmpty || element[key]?.toString() == expected;
        }
        return (arguments['name']?.toString().trim().isNotEmpty == true ||
                arguments['automationId']?.toString().trim().isNotEmpty == true ||
                arguments['className']?.toString().trim().isNotEmpty == true ||
                arguments['controlType']?.toString().trim().isNotEmpty == true) &&
            matches('name') &&
            matches('automationId') &&
            matches('className') &&
            matches('controlType');
      });
      if (found) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw PlatformException(
      code: 'UI_ELEMENT_TIMEOUT',
      message: 'انتهت مهلة انتظار عنصر UI Automation في النافذة: $windowTitle',
    );
  }

  Future<void> cancelMacroRecording() async {
    try {
      await invokeAutomation<void>('cancel_macro_recording');
    } on MissingPluginException {
      // Older runners may not expose macro recording. Disposal must remain safe.
    } on PlatformException {
      // The native runner is already shutting down; no UI action is possible.
    }
  }
}

/// Factory used by the page and tests to avoid constructing platform channels
/// in unrelated model/service tests.
final nativeAutomationService = NativeAutomationService();
