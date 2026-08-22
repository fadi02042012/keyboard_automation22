import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keyboard_automation/core/services/native_automation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('keyboard_automation/keyboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('getMousePosition sends an empty argument map and parses coordinates', () async {
    dynamic receivedArguments;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'get_mouse_position');
      receivedArguments = call.arguments;
      return <String, dynamic>{'x': 321, 'y': 654};
    });

    final service = NativeAutomationService(automationChannel: channel);
    final position = await service.getMousePosition();

    expect(receivedArguments, isA<Map>());
    expect(receivedArguments, isEmpty);
    expect(position, <String, int>{'x': 321, 'y': 654});
  });

  test('getMousePosition returns null for an invalid native payload', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, dynamic>{'x': 'not-a-number', 'y': 10};
    });

    final service = NativeAutomationService(automationChannel: channel);
    expect(await service.getMousePosition(), isNull);
  });
}

