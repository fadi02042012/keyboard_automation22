import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_automation/core/app_constants.dart';
import 'package:keyboard_automation/core/controllers/scenario_editor_controller.dart';
import 'package:keyboard_automation/core/models/automation_step.dart';
import 'package:keyboard_automation/core/models/scenario.dart';
import 'package:keyboard_automation/core/services/scenario_file_service.dart';

AutomationStep _textStep(String id, String value) {
  return AutomationStep(
    id: id,
    type: StepType.text,
    text: value,
  );
}

void main() {
  test('converts native macro payload aliases into visible steps', () {
    final keyboard = AutomationStep.fromMacroEvent(
      <String, dynamic>{
        'kind': 'keyboard',
        'keyName': 'enter',
        'modifierKeys': <String>['ctrl'],
        'duration': 25,
      },
      id: 'keyboard-1',
    );
    final mouse = AutomationStep.fromMacroEvent(
      <String, dynamic>{
        'action': 'click',
        'x': 100,
        'y': 200,
        'mouseButton': 'left',
        'isDoubleClick': true,
      },
      id: 'mouse-1',
    );

    expect(keyboard, isNotNull);
    expect(keyboard!.key, 'ENTER');
    expect(keyboard.modifiers, contains('CTRL'));
    expect(mouse, isNotNull);
    expect(mouse!.x, 100);
    expect(mouse.doubleClick, isTrue);
  });

  test('keeps the active window title on every recorded step', () {
    final step = AutomationStep.fromMacroEvent(
      <String, dynamic>{
        'type': 'mouse',
        'x': 300,
        'y': 400,
        'button': 'left',
        'window': 'المفكرة - مستند جديد',
      },
      id: 'mouse-window-1',
      targetWindow: 'نافذة احتياطية',
    );

    expect(step, isNotNull);
    expect(step!.targetWindow, 'المفكرة - مستند جديد');
  });

  test('preserves Run-dialog Enter and ALT+TAB transition metadata', () {
    final enter = AutomationStep.fromMacroEvent(
      <String, dynamic>{
        'type': 'key',
        'key': 'ENTER',
        'window': 'علامة تبويب جديدة - Google Chrome',
        'windowChanged': true,
        'previousWindow': 'تشغيل',
      },
      id: 'run-enter-1',
    );
    final altTab = AutomationStep.fromMacroEvent(
      <String, dynamic>{
        'type': 'key',
        'key': 'TAB',
        'modifiers': <String>['ALT'],
        'window': 'Google Chrome',
        'windowChanged': true,
        'previousWindow': 'تشغيل',
      },
      id: 'alt-tab-1',
    );

    expect(enter, isNotNull);
    expect(enter!.key, 'ENTER');
    expect(enter.targetWindow, 'علامة تبويب جديدة - Google Chrome');
    expect(enter.previousWindow, 'تشغيل');
    expect(enter.windowChanged, isTrue);
    expect(altTab, isNotNull);
    expect(altTab!.key, 'TAB');
    expect(altTab.modifiers, contains('ALT'));
    expect(altTab.previousWindow, 'تشغيل');
    expect(altTab.targetWindow, 'Google Chrome');
  });

  test('stores native window transitions on the first step in the new window', () {
    final step = AutomationStep.fromMacroEvent(
      <String, dynamic>{
        'type': 'key',
        'key': 'ENTER',
        'window': 'الآلة الحاسبة',
        'windowChanged': true,
        'previousWindow': 'المفكرة - مستند جديد',
      },
      id: 'window-transition-1',
    );

    expect(step, isNotNull);
    expect(step!.targetWindow, 'الآلة الحاسبة');
    expect(step.windowChanged, isTrue);
    expect(step.previousWindow, 'المفكرة - مستند جديد');

    final restored = AutomationStep.fromJson(step.toJson());
    expect(restored.windowChanged, isTrue);
    expect(restored.previousWindow, 'المفكرة - مستند جديد');
    expect(restored.targetWindow, 'الآلة الحاسبة');
  });

  test('converts native Unicode key payloads into text and preserves Arabic', () {
    final arabic = AutomationStep.fromMacroEvent(
      {
        'type': 'key',
        'key': 'A',
        'text': 'ش',
        'window': 'المفكرة',
      },
      id: 'arabic',
    );
    final latin = AutomationStep.fromMacroEvent(
      {
        'type': 'key',
        'key': 'A',
        'text': 'A',
        'window': 'المفكرة',
        'delayMs': 100,
      },
      id: 'latin',
    );

    expect(arabic?.type, StepType.text);
    expect(arabic?.text, 'ش');
    expect(latin?.type, StepType.text);
    expect(latin?.text, 'A');

    final grouped = coalesceRecordedTextSteps([arabic!, latin!]);
    expect(grouped, hasLength(1));
    expect(grouped.single.text, 'شA');
  });

  test('does not merge native text across a window transition', () {
    final grouped = coalesceRecordedTextSteps([
      AutomationStep(
        id: 'first',
        type: StepType.text,
        text: '12',
        targetWindow: 'نافذة 1',
      ),
      AutomationStep(
        id: 'second',
        type: StepType.text,
        text: '34',
        delayMs: 100,
        targetWindow: 'نافذة 2',
        windowChanged: true,
        previousWindow: 'نافذة 1',
      ),
    ]);

    expect(grouped, hasLength(2));
    expect(grouped[0].text, '12');
    expect(grouped[1].text, '34');
    expect(grouped[1].windowChanged, isTrue);
  });

  test('groups consecutive numeric input into one text step', () {
    final steps = <AutomationStep>[
      AutomationStep(id: '1', type: StepType.key, key: '1'),
      AutomationStep(id: '2', type: StepType.key, key: '2', delayMs: 200),
      AutomationStep(id: 'dash', type: StepType.key, key: '-', delayMs: 180),
      AutomationStep(id: '0', type: StepType.key, key: '0', delayMs: 180),
      AutomationStep(id: '8', type: StepType.key, key: '8', delayMs: 180),
      AutomationStep(id: 'enter', type: StepType.key, key: 'ENTER', delayMs: 180),
    ];

    final grouped = coalesceRecordedTextSteps(steps);

    expect(grouped, hasLength(2));
    expect(grouped.first.type, StepType.text);
    expect(grouped.first.text, '12-08');
    expect(grouped.last.type, StepType.key);
    expect(grouped.last.key, 'ENTER');
  });

  test('does not merge numeric input across a window transition', () {
    final steps = <AutomationStep>[
      AutomationStep(id: '1', type: StepType.key, key: '1', targetWindow: 'نافذة 1'),
      AutomationStep(
        id: '2',
        type: StepType.key,
        key: '2',
        delayMs: 100,
        targetWindow: 'نافذة 2',
        windowChanged: true,
        previousWindow: 'نافذة 1',
      ),
    ];

    final grouped = coalesceRecordedTextSteps(steps);

    expect(grouped, hasLength(2));
    expect(grouped[0].text, '1');
    expect(grouped[1].text, '2');
    expect(grouped[1].windowChanged, isTrue);
  });

  group('ScenarioFileService', () {
    const service = ScenarioFileService();

    test('exports a versioned document and round-trips Arabic content', () {
      final scenario = Scenario(
        id: 'scenario-1',
        name: 'سيناريو عربي',
        steps: [_textStep('step-1', 'مرحبا بالعالم')],
      );

      final bytes = service.encodeScenario(
        scenario: scenario,
        appVersion: kAppVersion,
      );
      final decoded = service.decodeScenario(utf8.decode(bytes));

      expect(decoded.name, 'سيناريو عربي');
      expect(decoded.schemaVersion, 1);
      expect(decoded.wasLegacyList, isFalse);
      expect(decoded.steps, hasLength(1));
      expect(decoded.steps.single.text, 'مرحبا بالعالم');
      expect(decoded.appVersion, kAppVersion);
    });

    test('round-trips semantic command timing and selector fields through a file', () {
      final scenario = Scenario(
        id: 'semantic-scenario',
        name: 'أمر دلالي',
        steps: [
          AutomationStep(
            id: 'semantic-1',
            type: StepType.semanticCommand,
            command: 'set_value',
            commandArguments: <String, dynamic>{
              'name': 'التاريخ',
              'controlType': '50004',
              'value': '19-08-2026',
            },
            waitTimeoutMs: 7000,
            delayMs: 250,
          ),
        ],
      );

      final decoded = service.decodeScenario(
        utf8.decode(service.encodeScenario(scenario: scenario, appVersion: kAppVersion)),
      );
      final step = decoded.steps.single;

      expect(step.type, StepType.semanticCommand);
      expect(step.command, 'set_value');
      expect(step.commandArguments['controlType'], '50004');
      expect(step.commandArguments['value'], '19-08-2026');
      expect(step.waitTimeoutMs, 7000);
      expect(step.delayMs, 250);
    });

    test('imports the legacy list format', () {
      final decoded = service.decodeScenario(
        jsonEncode([
          {'action': 'key', 'key': 'a'},
        ]),
      );

      expect(decoded.wasLegacyList, isTrue);
      expect(decoded.name, 'سيناريو مستورد');
      expect(decoded.steps.single.type, StepType.key);
    });

    test('rejects unsupported schema versions and malformed roots', () {
      expect(
        () => service.decodeScenario(
          jsonEncode({
            'schemaVersion': 2,
            'type': ScenarioFileService.documentType,
            'steps': [
              {'action': 'text', 'value': 'x'},
            ],
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => service.decodeScenario(jsonEncode({'steps': 'invalid'})),
        throwsFormatException,
      );
    });

    test('keeps valid steps and rejects files with no valid steps', () {
      final decoded = service.decodeScenario(
        jsonEncode({
          'schemaVersion': 1,
          'type': ScenarioFileService.documentType,
          'steps': [
            {'action': 'text', 'value': 'valid'},
            'invalid-step',
          ],
        }),
      );
      expect(decoded.steps, hasLength(1));
      expect(decoded.steps.single.text, 'valid');

      expect(
        () => service.decodeScenario(
          jsonEncode({
            'steps': ['invalid-step'],
          }),
        ),
        throwsFormatException,
      );
    });
  });

  group('ScenarioEditorController', () {
    test('undoes and redoes bounded snapshots without sharing mutable steps', () {
      final controller = ScenarioEditorController();
      final initial = [_textStep('step-1', 'one')];
      controller.capture(initial);
      final changed = [_textStep('step-1', 'two')];

      final undo = controller.undo(changed);
      expect(undo, isNotNull);
      expect(undo!.single.text, 'one');

      final redo = controller.redo(undo);
      expect(redo, isNotNull);
      expect(redo!.single.text, 'two');
    });

    test('new capture clears redo history', () {
      final controller = ScenarioEditorController();
      final first = [_textStep('step-1', 'one')];
      controller.capture(first);
      final second = [_textStep('step-1', 'two')];
      expect(controller.undo(second), isNotNull);
      expect(controller.canRedo, isTrue);

      controller.capture(first);
      expect(controller.canRedo, isFalse);
    });
  });
}
