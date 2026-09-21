enum StepType {
  text,
  key,
  delay,
  mouse,
  loop,
  setCounter,
  incrementCounter,
  waitForWindow,
  semanticCommand,
}

class AutomationStep {
  AutomationStep({
    required this.id,
    required this.type,
    this.text = '',
    this.key = '',
    this.modifiers = const [],
    this.repeat = 1,
    this.delayMs = 0,
    this.x = 0,
    this.y = 0,
    this.button = 'left',
    this.doubleClick = false,
    this.loopCount = 1,
    this.loopDelayMs = 500,
    this.counterName = '',
    this.counterValue = 0,
    this.incrementAmount = 1,
    this.targetWindow = '',
    this.windowAlias = '',
    this.windowMatch = 'title',
    this.windowChanged = false,
    this.previousWindow,
    this.waitTimeoutMs = 5000,
    this.command = '',
    this.commandArguments = const {},
  });

  final String id;
  StepType type;
  String text;
  String key;
  List<String> modifiers;
  int repeat;
  int delayMs;
  int x;
  int y;
  String button;
  bool doubleClick;
  int loopCount;
  int loopDelayMs;
  String counterName;
  int counterValue;
  int incrementAmount;
  String targetWindow;
  /// Logical window identity. Unlike the visible title, this remains stable
  /// while a browser changes its page/tab title.
  String windowAlias;
  /// `title` keeps legacy behavior; `alias` resolves by runtime HWND affinity.
  String windowMatch;
  bool windowChanged;
  String? previousWindow;
  int waitTimeoutMs;
  /// Stable, semantic command name such as `set_value`, `invoke`, or `wait_for_element`.
  String command;
  /// JSON-compatible arguments for the semantic command.
  Map<String, dynamic> commandArguments;

  static int _idCounter = 0;

  AutomationStep copy({String? id}) {
    return AutomationStep(
      id: id ?? this.id,
      type: type,
      text: text,
      key: key,
      modifiers: List.from(modifiers),
      repeat: repeat,
      delayMs: delayMs,
      x: x,
      y: y,
      button: button,
      doubleClick: doubleClick,
      loopCount: loopCount,
      loopDelayMs: loopDelayMs,
      counterName: counterName,
      counterValue: counterValue,
      incrementAmount: incrementAmount,
      targetWindow: targetWindow,
      windowAlias: windowAlias,
      windowMatch: windowMatch,
      windowChanged: windowChanged,
      previousWindow: previousWindow,
      waitTimeoutMs: waitTimeoutMs,
      command: command,
      commandArguments: Map<String, dynamic>.from(commandArguments),
    );
  }

  static String _getActionName(StepType type) {
    switch (type) {
      case StepType.text:
        return 'text';
      case StepType.key:
        return 'key';
      case StepType.delay:
        return 'wait';
      case StepType.mouse:
        return 'mouse';
      case StepType.setCounter:
        return 'set_counter';
      case StepType.incrementCounter:
        return 'inc_counter';
      case StepType.waitForWindow:
        return 'wait_for_window';
      case StepType.loop:
        return 'loop';
      case StepType.semanticCommand:
        return 'semantic_command';
    }
  }

  static StepType _getTypeFromAction(String action) {
    switch (action) {
      case 'text':
        return StepType.text;
      case 'key':
        return StepType.key;
      case 'wait':
        return StepType.delay;
      case 'mouse':
        return StepType.mouse;
      case 'set_counter':
        return StepType.setCounter;
      case 'inc_counter':
        return StepType.incrementCounter;
      case 'wait_for_window':
        return StepType.waitForWindow;
      case 'loop':
        return StepType.loop;
      case 'semantic_command':
      case 'command':
        return StepType.semanticCommand;
      default:
        return StepType.text;
    }
  }

  Map<String, dynamic> toJson() => {
        // Keep the stable step id in persisted files so editor state, logs,
        // and future references remain attached to the same step after import.
        'id': id,
        'action': _getActionName(type),
        if (type == StepType.text) ...{
          'value': text,
          if (delayMs > 0) 'delay': delayMs,
          if (repeat > 1) 'repeat': repeat,
          if (targetWindow.isNotEmpty) 'window': targetWindow,
          if (windowMatch != 'title') 'windowMatch': windowMatch,
        },
        if (type == StepType.key) ...{
          'key': key,
          if (modifiers.isNotEmpty) 'modifiers': modifiers,
          if (repeat > 1) 'repeat': repeat,
          if (delayMs > 0) 'delay': delayMs,
          if (targetWindow.isNotEmpty) 'window': targetWindow,
        },
        if (type == StepType.delay) ...{
          'ms': delayMs,
        },
        if (type == StepType.mouse) ...{
          'x': x,
          'y': y,
          'button': button,
          if (doubleClick) 'doubleClick': true,
          if (repeat > 1) 'repeat': repeat,
          if (delayMs > 0) 'delay': delayMs,
          if (targetWindow.isNotEmpty) 'window': targetWindow,
        },
        if (type == StepType.setCounter) ...{
          'name': counterName,
          'value': counterValue,
        },
        if (type == StepType.incrementCounter) ...{
          'name': counterName,
          'amount': incrementAmount,
        },
        if (type == StepType.waitForWindow) ...{
          'window': targetWindow,
          'timeout': waitTimeoutMs,
        },
        if (type == StepType.loop) ...{
          'count': loopCount,
          'delay': loopDelayMs,
        },
        if (type == StepType.semanticCommand) ...{
          'command': command,
          'arguments': Map<String, dynamic>.from(commandArguments),
          if (targetWindow.isNotEmpty) 'window': targetWindow,
          if (waitTimeoutMs != 5000) 'timeout': waitTimeoutMs,
          if (delayMs > 0) 'delay': delayMs,
        },
        if (windowAlias.isNotEmpty) 'windowId': windowAlias,
        if (windowMatch != 'title') 'windowMatch': windowMatch,
        if (windowChanged) 'windowChanged': true,
        if (previousWindow?.trim().isNotEmpty == true) 'previousWindow': previousWindow?.trim(),
      }..removeWhere((key, value) => value == null);

  static int asInt(dynamic value, int fallback, {int min = -2147483648, int max = 2147483647}) {
    final parsed = value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    if (parsed == null) return fallback;
    return parsed.clamp(min, max).toInt();
  }

  static String asString(dynamic value, [String fallback = '']) {
    return value is String ? value : (value?.toString() ?? fallback);
  }

  static bool _asBool(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }

  static List<String> _asStringList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().map((item) => item.trim().toUpperCase()).where((item) => item.isNotEmpty).toList(growable: false);
  }

  /// Converts one native macro event into a backward-compatible automation step.
  /// Returns null for unsupported or malformed events.
  static AutomationStep? fromMacroEvent(
    Map<String, dynamic> event, {
    required String id,
    String targetWindow = '',
  }) {
    final delayMs = asInt(event['delayMs'] ?? event['delay'] ?? event['duration'], 0, min: 0, max: 86400000);
    final recordedWindow = asString(
      event['targetWindow'] ??
          event['window'] ??
          event['windowTitle'] ??
          event['window_title'] ??
          event['activeWindow'] ??
          targetWindow,
    ).trim();
    final windowChanged = _asBool(event['windowChanged'] ?? event['window_changed']);
    final previousWindow = asString(event['previousWindow'] ?? event['previous_window']).trim();
    final rawType = asString(event['type'] ?? event['kind'] ?? event['action']).trim().toLowerCase();
    final type = rawType == 'keyboard' || rawType == 'keypress' || rawType == 'key_down'
        ? 'key'
        : rawType == 'click' || rawType == 'mouse_click' || rawType == 'mouse_down'
            ? 'mouse'
            : rawType;
    if (type == 'key') {
      // New Windows recordings include the character produced by the active
      // keyboard layout. Prefer it over the virtual-key name so Arabic,
      // English, shifted symbols, Caps Lock, and AltGr are recorded exactly
      // as typed. Legacy runners do not send `text`, so the key fallback below
      // remains backward-compatible.
      final producedText = asString(event['text']);
      if (producedText.isNotEmpty) {
        return AutomationStep(
          id: id,
          type: StepType.text,
          text: producedText,
          delayMs: delayMs,
          targetWindow: recordedWindow,
          windowAlias: asString(event['windowId'] ?? event['windowAlias'] ?? event['window_alias']),
          windowMatch: asString(event['windowMatch'] ?? event['window_match'], 'title'),
          windowChanged: windowChanged,
          previousWindow: previousWindow.isEmpty ? null : previousWindow,
        );
      }

      final key = asString(event['key'] ?? event['keyName'] ?? event['virtualKey']).trim().toUpperCase();
      if (key.isEmpty) return null;
      return AutomationStep(
        id: id,
        type: StepType.key,
        key: key,
        modifiers: _asStringList(event['modifiers'] ?? event['modifierKeys']),
        delayMs: delayMs,
        targetWindow: recordedWindow,
        windowAlias: asString(event['windowAlias'] ?? event['window_alias']),
        windowMatch: asString(event['windowMatch'] ?? event['window_match'], 'title'),
        windowChanged: windowChanged,
        previousWindow: previousWindow.isEmpty ? null : previousWindow,
      );
    }
    if (type == 'mouse' || event.containsKey('x') || event.containsKey('y')) {
      final button = asString(event['button'] ?? event['mouseButton'], 'left').trim().toLowerCase();
      if (!{'left', 'right', 'middle'}.contains(button)) return null;
      return AutomationStep(
        id: id,
        type: StepType.mouse,
        x: asInt(event['x'], 0, min: -100000, max: 100000),
        y: asInt(event['y'], 0, min: -100000, max: 100000),
        button: button,
        doubleClick: _asBool(event['doubleClick'] ?? event['double_click'] ?? event['isDoubleClick']),
        delayMs: delayMs,
        targetWindow: recordedWindow,
        windowChanged: windowChanged,
        previousWindow: previousWindow.isEmpty ? null : previousWindow,
      );
    }
    return null;
  }

  factory AutomationStep.fromJson(Map<String, dynamic> json) {
    final action = asString(json['action'], 'text').trim().toLowerCase();
    final rawId = json['id'];
    final id = rawId == null || rawId.toString().trim().isEmpty
        ? '${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}'
        : rawId.toString();
    final type = _getTypeFromAction(action);
    final modifiers = _asStringList(json['modifiers']);
    final windowChanged = _asBool(json['windowChanged'] ?? json['window_changed']);
    final previousWindow = asString(json['previousWindow'] ?? json['previous_window']).trim();

    switch (type) {
      case StepType.text:
        return AutomationStep(
          id: id,
          type: type,
          text: asString(json['value'] ?? json['text']),
          repeat: asInt(json['repeat'], 1, min: 1, max: 100000),
          delayMs: asInt(json['delay'] ?? json['delayMs'], 0, min: 0, max: 86400000),
          targetWindow: asString(json['window'] ?? json['targetWindow']).trim(),

          windowAlias: asString(json['windowId'] ?? json['windowAlias'] ?? json['window_alias']).trim(),
          windowMatch: asString(json['windowMatch'] ?? json['window_match'], 'title').trim().toLowerCase(),
          windowChanged: windowChanged,
          previousWindow: previousWindow.isEmpty ? null : previousWindow,
        );
      case StepType.key:
        return AutomationStep(
          id: id,
          type: type,
          key: asString(json['key'], 'ENTER').trim().toUpperCase(),
          modifiers: modifiers,
          repeat: asInt(json['repeat'], 1, min: 1, max: 100000),
          delayMs: asInt(json['delay'] ?? json['delayMs'], 0, min: 0, max: 86400000),
          targetWindow: asString(json['window'] ?? json['targetWindow']).trim(),

          windowAlias: asString(json['windowId'] ?? json['windowAlias'] ?? json['window_alias']).trim(),

          windowMatch: asString(json['windowMatch'] ?? json['window_match'], 'title').trim().toLowerCase(),
          windowChanged: windowChanged,
          previousWindow: previousWindow.isEmpty ? null : previousWindow,
        );
      case StepType.delay:
        return AutomationStep(
          id: id,
          type: type,
          delayMs: asInt(json['ms'] ?? json['delayMs'], 1000, min: 0, max: 86400000),
        );
      case StepType.mouse:
        final button = asString(json['button'], 'left').trim().toLowerCase();
        return AutomationStep(
          id: id,
          type: type,
          x: asInt(json['x'], 0, min: -100000, max: 100000),
          y: asInt(json['y'], 0, min: -100000, max: 100000),
          button: {'left', 'right', 'middle'}.contains(button) ? button : 'left',
          doubleClick: _asBool(json['doubleClick'] ?? json['double_click']),
          repeat: asInt(json['repeat'], 1, min: 1, max: 100000),
          delayMs: asInt(json['delay'] ?? json['delayMs'], 0, min: 0, max: 86400000),
          targetWindow: asString(json['window'] ?? json['targetWindow']).trim(),

          windowAlias: asString(json['windowAlias'] ?? json['window_alias']).trim(),

          windowMatch: asString(json['windowMatch'] ?? json['window_match'], 'title').trim().toLowerCase(),
          windowChanged: windowChanged,
          previousWindow: previousWindow.isEmpty ? null : previousWindow,
        );
      case StepType.setCounter:
        return AutomationStep(
          id: id,
          type: type,
          counterName: asString(json['name']).trim(),
          counterValue: asInt(json['value'] ?? json['counterValue'], 1),
        );
      case StepType.incrementCounter:
        return AutomationStep(
          id: id,
          type: type,
          counterName: asString(json['name']).trim(),
          incrementAmount: asInt(json['amount'] ?? json['incrementAmount'], 1),
        );
      case StepType.waitForWindow:
        return AutomationStep(
          id: id,
          type: type,
          targetWindow: asString(json['window'] ?? json['targetWindow']).trim(),

          windowAlias: asString(json['windowAlias'] ?? json['window_alias']).trim(),
          windowMatch: asString(json['windowMatch'] ?? json['window_match'], 'title').trim().toLowerCase(),
          waitTimeoutMs: asInt(json['timeout'] ?? json['waitTimeoutMs'], 5000, min: 100, max: 30000),
        );
      case StepType.loop:
        return AutomationStep(
          id: id,
          type: type,
          loopCount: asInt(json['count'] ?? json['loopCount'], 1, min: 1, max: 100000),
          loopDelayMs: asInt(json['delay'] ?? json['loopDelayMs'], 500, min: 0, max: 86400000),
        );
      case StepType.semanticCommand:
        final rawArguments = json['arguments'];
        return AutomationStep(
          id: id,
          type: type,
          command: asString(json['command'] ?? json['name']).trim(),
          commandArguments: rawArguments is Map
              ? Map<String, dynamic>.from(rawArguments)
              : <String, dynamic>{},
          targetWindow: asString(json['window'] ?? json['targetWindow']).trim(),

          windowAlias: asString(json['windowAlias'] ?? json['window_alias']).trim(),

          windowMatch: asString(json['windowMatch'] ?? json['window_match'], 'title').trim().toLowerCase(),
          waitTimeoutMs: asInt(json['timeout'] ?? json['waitTimeoutMs'], 5000, min: 100, max: 30000),
          delayMs: asInt(json['delay'] ?? json['delayMs'], 0, min: 0, max: 86400000),
        );
    }
  }
}


/// Collapses consecutive recorded text into one text step.
///
/// New native recordings already contain the exact Unicode character produced
/// by Windows. The numeric/punctuation conversion below remains as a fallback
/// for recordings made by older Windows runners that only emitted key names.
List<AutomationStep> coalesceRecordedTextSteps(
  List<AutomationStep> steps, {
  int maxGapMs = 1200,
}) {
  final result = <AutomationStep>[];
  for (final step in steps) {
    final previous = result.isEmpty ? null : result.last;

    if (step.type == StepType.text && step.text.isNotEmpty) {
      final canMergeText = previous != null &&
          previous.type == StepType.text &&
          previous.targetWindow == step.targetWindow &&
          !step.windowChanged &&
          step.previousWindow == null &&
          step.delayMs <= maxGapMs;
      if (canMergeText) {
        previous.text += step.text;
        continue;
      }
      result.add(step);
      continue;
    }

    final character = _recordedTextCharacter(step);
    if (character == null || step.repeat != 1) {
      result.add(step);
      continue;
    }

    final canMerge = previous != null &&
        previous.type == StepType.text &&
        previous.targetWindow == step.targetWindow &&
        !step.windowChanged &&
        step.previousWindow == null &&
        step.delayMs <= maxGapMs;

    if (canMerge) {
      previous.text += character;
      continue;
    }

    result.add(
      AutomationStep(
        id: step.id,
        type: StepType.text,
        text: character,
        delayMs: step.delayMs,
        targetWindow: step.targetWindow,
        windowChanged: step.windowChanged,
        previousWindow: step.previousWindow,
      ),
    );
  }
  return result;
}

String? _recordedTextCharacter(AutomationStep step) {
  if (step.type != StepType.key || step.modifiers.isNotEmpty) return null;
  final key = step.key.trim().toUpperCase();
  if (key == 'SPACE') return ' ';
  if (RegExp(r'^[0-9]$').hasMatch(key)) return key;
  const punctuation = <String>{'-', '/', '.', ',', '=', '_'};
  return punctuation.contains(key) ? key : null;
}

