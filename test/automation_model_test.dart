import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_automation/core/models/automation_step.dart';
import 'package:keyboard_automation/core/models/scenario.dart';

void main() {
  group('AutomationStep serialization', () {
    test('round-trips the current export schema', () {
      final original = AutomationStep(
        id: 'step-1',
        type: StepType.key,
        key: 'c',
        modifiers: ['ctrl'],
        repeat: 2,
        delayMs: 150,
        targetWindow: 'Notepad',
      );

      final restored = AutomationStep.fromJson(original.toJson());

      expect(restored.type, StepType.key);
      expect(restored.key, 'C');
      expect(restored.modifiers, ['CTRL']);
      expect(restored.repeat, 2);
      expect(restored.delayMs, 150);
      expect(restored.targetWindow, 'Notepad');
    });

    test('round-trips semantic UI Automation commands', () {
      final original = AutomationStep(
        id: 'semantic-1',
        type: StepType.semanticCommand,
        command: 'set_value',
        commandArguments: {
          'automationId': 'amountInput',
          'className': 'Edit',
          'controlType': '50004',
          'value': '19-08-2026',
        },
        targetWindow: 'INWARDR5: معاينة قبل الطباعة',
        delayMs: 250,
      );

      final restored = AutomationStep.fromJson(original.toJson());

      expect(restored.type, StepType.semanticCommand);
      expect(restored.command, 'set_value');
      expect(restored.commandArguments['automationId'], 'amountInput');
      expect(restored.commandArguments['controlType'], '50004');
      expect(restored.commandArguments['value'], '19-08-2026');
      expect(restored.targetWindow, 'INWARDR5: معاينة قبل الطباعة');
      expect(restored.delayMs, 250);
    });

    test('round-trips wait_for_element semantic command and timeout', () {
      final original = AutomationStep(
        id: 'wait-1',
        type: StepType.semanticCommand,
        command: 'wait_for_element',
        commandArguments: {'automationId': 'readyButton', 'className': 'Button'},
        targetWindow: 'Target Window',
        waitTimeoutMs: 12000,
      );

      final restored = AutomationStep.fromJson(original.toJson());

      expect(restored.command, 'wait_for_element');
      expect(restored.commandArguments['automationId'], 'readyButton');
      expect(restored.commandArguments['className'], 'Button');
      expect(restored.waitTimeoutMs, 12000);
      expect(restored.targetWindow, 'Target Window');
    });

    test('accepts legacy numeric fields and clamps unsafe values', () {
      final restored = AutomationStep.fromJson({
        'action': 'mouse',
        'x': '999999',
        'y': -999999,
        'button': 'unknown',
        'repeat': 0,
        'delay': -10,
        'double_click': 'true',
      });

      expect(restored.type, StepType.mouse);
      expect(restored.x, 100000);
      expect(restored.y, -100000);
      expect(restored.button, 'left');
      expect(restored.repeat, 1);
      expect(restored.delayMs, 0);
      expect(restored.doubleClick, isTrue);
    });
  });

  group('Macro event conversion', () {
    test('converts key and mouse events with normalized values', () {
      final key = AutomationStep.fromMacroEvent(
        {
          'type': 'key',
          'key': 'a',
          'modifiers': ['ctrl', 'shift'],
          'delayMs': '120',
        },
        id: 'macro-key',
        targetWindow: 'Notepad',
      );
      final mouse = AutomationStep.fromMacroEvent(
        {
          'type': 'mouse',
          'x': '999999',
          'y': '-999999',
          'button': 'RIGHT',
          'double_click': 'true',
        },
        id: 'macro-mouse',
      );

      expect(key?.type, StepType.key);
      expect(key?.key, 'A');
      expect(key?.modifiers, ['CTRL', 'SHIFT']);
      expect(key?.delayMs, 120);
      expect(key?.targetWindow, 'Notepad');
      expect(mouse?.type, StepType.mouse);
      expect(mouse?.x, 100000);
      expect(mouse?.y, -100000);
      expect(mouse?.button, 'right');
      expect(mouse?.doubleClick, isTrue);
    });

    test('ignores unsupported or invalid events', () {
      expect(
        AutomationStep.fromMacroEvent({'type': 'move'}, id: 'unsupported'),
        isNull,
      );
      expect(
        AutomationStep.fromMacroEvent({'type': 'mouse', 'button': 'pen'}, id: 'invalid'),
        isNull,
      );
    });
  });

  test('scenario parser preserves valid steps when one step is malformed', () {
    final scenario = Scenario.fromJson({
      'id': 'scenario-1',
      'name': 'Demo',
      'steps': [
        {'action': 'text', 'value': 'hello'},
        'not-a-step',
      ],
    });

    expect(scenario.name, 'Demo');
    expect(scenario.steps, hasLength(1));
    expect(scenario.steps.single.text, 'hello');
  });
}
