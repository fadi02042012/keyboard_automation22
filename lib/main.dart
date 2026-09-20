import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'core/app_logger.dart';
import 'core/app_constants.dart';
import 'core/models/automation_step.dart';
import 'core/models/scenario.dart';
import 'core/models/shortcut.dart';
import 'core/controllers/scenario_editor_controller.dart';
import 'core/services/native_automation_service.dart';
import 'core/services/automation_executor.dart';
import 'core/services/scenario_storage.dart';
import 'core/services/scenario_file_service.dart';

void main() {
  runApp(const KeyboardAutomationApp());
}

class KeyboardAutomationApp extends StatelessWidget {
  const KeyboardAutomationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'أتمتة لوحة المفاتيح',
      locale: const Locale('ar'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ar'), Locale('en')],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
        fontFamily: 'Segoe UI',
        visualDensity: VisualDensity.standard,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.indigo, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        cardTheme: CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const AutomationHomePage(),
    );
  }
}

class AutomationHomePage extends StatefulWidget {
  const AutomationHomePage({super.key});

  @override
  State<AutomationHomePage> createState() => _AutomationHomePageState();
}

class _AutomationHomePageState extends State<AutomationHomePage> {
  final NativeAutomationService _nativeAutomation = nativeAutomationService;
  late final AutomationExecutor _executor;
  final ScenarioStorage _scenarioStorage = const ScenarioStorage();
  final ScenarioFileService _scenarioFileService = const ScenarioFileService();
  final ScenarioEditorController _editorController = ScenarioEditorController();
  final ScrollController _stepsScrollController = ScrollController();
  String _stepSearchQuery = '';

  // ==================== المتغيرات الرئيسية ====================
  final List<AutomationStep> _steps = [];
  String _currentScenarioName = 'اكتب اسم';
  String? _currentScenarioId;

  bool _running = false;
  bool _stopRequested = false;
  int? _currentStep;
  int _currentLoopIteration = 0;
  int _totalLoopIterations = 1;
  int _currentScenarioIteration = 0;
  int _totalScenarioIterations = 1;

  Timer? _delayTimer;
  Completer<void>? _pendingDelay;
  int _idCounter = 0;

  // ==================== إعدادات التأخير ====================
  bool _randomDelayEnabled = false;
  int _randomDelayMin = 100;
  int _randomDelayMax = 500;

  // ==================== إعدادات التكرار ====================
  int? _loopRangeStart;
  int? _loopRangeEnd;
  int _loopRangeCount = 1;
  int _loopDelayMs = 500;
  List<int> _selectedRepeatSteps = [];

  // ==================== إعدادات تكرار السيناريو ====================
  bool _scenarioPeriodic = false;
  int _scenarioRepeatCount = 1;
  int _scenarioIntervalMs = 1000;

  // ==================== العدادات ====================
  Map<String, int> _counterValues = {};
  final Map<String, int> _counterStarts = {};

  // ==================== النوافذ ====================
  List<Map<String, String>> _openWindows = [];
  String? _selectedWindowForDropdown;
  Timer? _windowsRefreshTimer;
  bool _refreshingWindows = false;

  // ==================== أداء وتحسين ====================
  bool _debugMode = false;
  int _maxRetries = 3;
  bool _useFastMode = false;

  // ==================== تسجيل الماكرو ====================
  bool _macroRecording = false;
  bool _macroBusy = false;
  int _macroEventCount = 0;

  // ==================== الاختصارات الجاهزة ====================
  final Map<String, Shortcut> _shortcuts = {
    'نسخ (Ctrl+C)': Shortcut(
      key: 'C',
      modifiers: ['CTRL'],
      description: 'نسخ',
    ),
    'لصق (Ctrl+V)': Shortcut(
      key: 'V',
      modifiers: ['CTRL'],
      description: 'لصق',
    ),
    'قص (Ctrl+X)': Shortcut(
      key: 'X',
      modifiers: ['CTRL'],
      description: 'قص',
    ),
    'تراجع (Ctrl+Z)': Shortcut(
      key: 'Z',
      modifiers: ['CTRL'],
      description: 'تراجع',
    ),
    'إعادة (Ctrl+Y)': Shortcut(
      key: 'Y',
      modifiers: ['CTRL'],
      description: 'إعادة',
    ),
    'تحديد الكل (Ctrl+A)': Shortcut(
      key: 'A',
      modifiers: ['CTRL'],
      description: 'تحديد الكل',
    ),
    'حفظ (Ctrl+S)': Shortcut(
      key: 'S',
      modifiers: ['CTRL'],
      description: 'حفظ',
    ),
    'فتح (Ctrl+O)': Shortcut(
      key: 'O',
      modifiers: ['CTRL'],
      description: 'فتح',
    ),
    'جديد (Ctrl+N)': Shortcut(
      key: 'N',
      modifiers: ['CTRL'],
      description: 'جديد',
    ),
    'طباعة (Ctrl+P)': Shortcut(
      key: 'P',
      modifiers: ['CTRL'],
      description: 'طباعة',
    ),
    'بحث (Ctrl+F)': Shortcut(
      key: 'F',
      modifiers: ['CTRL'],
      description: 'بحث',
    ),
    'Enter': Shortcut(
      key: 'ENTER',
      modifiers: [],
      description: 'Enter',
    ),
    'Tab': Shortcut(
      key: 'TAB',
      modifiers: [],
      description: 'Tab',
    ),
    'Escape': Shortcut(
      key: 'ESC',
      modifiers: [],
      description: 'Escape',
    ),
    'Space': Shortcut(
      key: 'SPACE',
      modifiers: [],
      description: 'Space',
    ),
    'Backspace': Shortcut(
      key: 'BACKSPACE',
      modifiers: [],
      description: 'Backspace',
    ),
    'Delete': Shortcut(
      key: 'DELETE',
      modifiers: [],
      description: 'Delete',
    ),
    'السهم لأعلى': Shortcut(
      key: 'UP',
      modifiers: [],
      description: 'سهم لأعلى',
    ),
    'السهم لأسفل': Shortcut(
      key: 'DOWN',
      modifiers: [],
      description: 'سهم لأسفل',
    ),
    'السهم لليسار': Shortcut(
      key: 'LEFT',
      modifiers: [],
      description: 'سهم لليسار',
    ),
    'السهم لليمين': Shortcut(
      key: 'RIGHT',
      modifiers: [],
      description: 'سهم لليمين',
    ),
    'Home': Shortcut(
      key: 'HOME',
      modifiers: [],
      description: 'Home',
    ),
    'End': Shortcut(
      key: 'END',
      modifiers: [],
      description: 'End',
    ),
    'Page Up': Shortcut(
      key: 'PAGEUP',
      modifiers: [],
      description: 'Page Up',
    ),
    'Page Down': Shortcut(
      key: 'PAGEDOWN',
      modifiers: [],
      description: 'Page Down',
    ),
    'F1': Shortcut(key: 'F1', modifiers: [], description: 'F1 مساعدة'),
    'F2': Shortcut(key: 'F2', modifiers: [], description: 'F2 إعادة تسمية'),
    'F3': Shortcut(key: 'F3', modifiers: [], description: 'F3 بحث التالي'),
    'F4': Shortcut(key: 'F4', modifiers: [], description: 'F4'),
    'F5': Shortcut(key: 'F5', modifiers: [], description: 'F5 تحديث'),
    'F6': Shortcut(key: 'F6', modifiers: [], description: 'F6'),
    'F7': Shortcut(key: 'F7', modifiers: [], description: 'F7'),
    'F8': Shortcut(key: 'F8', modifiers: [], description: 'F8'),
    'F9': Shortcut(key: 'F9', modifiers: [], description: 'F9'),
    'F10': Shortcut(key: 'F10', modifiers: [], description: 'F10'),
    'F11': Shortcut(key: 'F11', modifiers: [], description: 'F11 ملء الشاشة'),
    'F12': Shortcut(key: 'F12', modifiers: [], description: 'F12 أدوات المطور'),
    'Windows - Run (Win+R)': Shortcut(
      key: 'R',
      modifiers: ['WIN'],
      description: 'فتح Run',
    ),
    'Windows - Explorer (Win+E)': Shortcut(
      key: 'E',
      modifiers: ['WIN'],
      description: 'فتح مستكشف الملفات',
    ),
    'Windows - Lock (Win+L)': Shortcut(
      key: 'L',
      modifiers: ['WIN'],
      description: 'قفل الجهاز',
    ),
    'Windows - Settings (Win+I)': Shortcut(
      key: 'I',
      modifiers: ['WIN'],
      description: 'فتح إعدادات Windows',
    ),
  };

  // ==================== دوال مساعدة ====================
  String _newId() {
    _idCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  void _logDebug(String message) {
    if (_debugMode) {
      AppLogger.debug(message);
    }
  }

  Future<void> _startMacroRecording() async {
    if (_running || _macroBusy || _macroRecording) return;
    setState(() {
      _macroBusy = true;
      _macroEventCount = 0;
    });
    try {
      AppLogger.info('Starting macro recording.', name: 'macro');
      final started = await _nativeAutomation.invokeAutomation<bool>('start_macro_recording') ?? false;
      if (!started) {
        throw Exception('تعذر تثبيت خطافات تسجيل لوحة المفاتيح والفأرة في Windows');
      }
      if (!mounted) {
        try {
          await _nativeAutomation.invokeAutomation('cancel_macro_recording');
        } catch (error, stackTrace) {
          AppLogger.warning(
            'Could not cancel macro recorder after page disposal.',
            error: error,
            stackTrace: stackTrace,
            name: 'macro',
          );
        }
        return;
      }
      setState(() {
        _macroRecording = true;
        _macroBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('بدأ التسجيل. نفّذ الخطوات في البرنامج المستهدف ثم اضغط إيقاف التسجيل.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _macroBusy = false);
      _handleError('تعذر بدء تسجيل الماكرو', exception: Exception(error.toString()));
    }
  }

  Future<void> _stopMacroRecording() async {
    if (!_macroRecording || _macroBusy) return;
    setState(() => _macroBusy = true);
    try {
      AppLogger.info('Stopping macro recording.', name: 'macro');
      final raw = await _nativeAutomation.invokeAutomation<dynamic>('stop_macro_recording');
      var recorded = <AutomationStep>[];
      final targetWindow = _inheritedTargetWindowForNewStep();

      // New Windows runners return {events: [...], count: n}; older runners
      // returned the event list directly. Accept both formats so an update of
      // the Dart layer cannot silently hide a valid native recording.
      dynamic rawEvents = raw;
      if (raw is Map) {
        rawEvents = raw['events'] ?? raw['recordedEvents'] ?? const [];
        _logDebug('Native macro payload: count=${raw['count']}, eventsType=${rawEvents.runtimeType}.');
      } else {
        _logDebug('Legacy native macro payload type=${raw.runtimeType}.');
      }

      var nativeEventCount = 0;
      var rejectedEventCount = 0;
      if (rawEvents is List) {
        nativeEventCount = rawEvents.length;
        for (final item in rawEvents) {
          if (item is! Map) {
            rejectedEventCount++;
            continue;
          }
          final event = <String, dynamic>{};
          item.forEach((key, value) {
            event[key.toString()] = value;
          });
          final step = AutomationStep.fromMacroEvent(
            event,
            id: _newId(),
            targetWindow: targetWindow,
          );
          if (step != null) {
            recorded.add(step);
          } else {
            rejectedEventCount++;
            _logDebug('Rejected native macro event: $event');
          }
        }
      }
      final convertedKeyCount = recorded.length;
      recorded = coalesceRecordedTextSteps(recorded);
      AppLogger.info(
        'Native macro result: nativeEvents=$nativeEventCount, converted=$convertedKeyCount, grouped=${recorded.length}, rejected=$rejectedEventCount.',
        name: 'macro',
      );

      if (!mounted) return;
      AppLogger.info('Macro recording converted to ${recorded.length} steps.', name: 'macro');
      _captureEditorChange();
      setState(() {
        _macroRecording = false;
        _macroBusy = false;
        _macroEventCount = recorded.length;
        // إظهار الخطوات المسجلة مباشرة حتى إذا كان المستخدم قد ترك بحثاً مفعلاً.
        _stepSearchQuery = '';
        _steps.addAll(recorded);
      });

      var saved = false;
      if (recorded.isNotEmpty) {
        saved = await _persistMacroRecording();
      }
      if (recorded.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_stepsScrollController.hasClients) return;
          _stepsScrollController.animateTo(
            _stepsScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(recorded.isEmpty
              ? nativeEventCount == 0
                  ? 'انتهى التسجيل، لكن Windows لم يُعد أي أحداث. أعد بناء نسخة Windows الأخيرة وتأكد من نجاح بدء التسجيل.'
                  : 'استلم التطبيق $nativeEventCount حدثاً، لكنه رفض $rejectedEventCount حدثاً أثناء التحويل.'
              : saved
                  ? 'تمت إضافة ${recorded.length} خطوة من أصل $nativeEventCount وحفظها تلقائياً في السيناريو.'
                  : 'تمت إضافة ${recorded.length} خطوة من أصل $nativeEventCount. تعذر الحفظ التلقائي؛ احفظ السيناريو يدوياً.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Stopping macro recording failed; requesting native cancellation.',
        error: error,
        stackTrace: stackTrace,
        name: 'macro',
      );
      try {
        await _nativeAutomation.invokeAutomation('cancel_macro_recording');
      } catch (cancelError, cancelStackTrace) {
        AppLogger.error(
          'Native macro cancellation after stop failure also failed.',
          error: cancelError,
          stackTrace: cancelStackTrace,
          name: 'macro',
        );
      }
      if (!mounted) return;
      setState(() {
        _macroRecording = false;
        _macroBusy = false;
      });
      _handleError('تعذر إيقاف تسجيل الماكرو', exception: Exception(error.toString()));
    }
  }

  Future<bool> _persistMacroRecording() async {
    try {
      final scenarios = await _loadScenarios();
      var scenarioId = _currentScenarioId;
      var scenarioName = _currentScenarioName.trim();
      final isUnnamed = scenarioName.isEmpty || scenarioName == 'اكتب اسم';

      if (scenarioId == null || isUnnamed) {
        final now = DateTime.now();
        final stamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
        scenarioId = _newId();
        scenarioName = 'تسجيل ماكرو $stamp';
      }

      final scenario = Scenario(
        id: scenarioId,
        name: scenarioName,
        steps: _cloneSteps(_steps),
      );
      final index = scenarios.indexWhere((item) => item.id == scenarioId);
      if (index == -1) {
        scenarios.add(scenario);
      } else {
        scenarios[index] = scenario;
      }

      final persisted = await _persistScenarios(scenarios);
      if (!persisted) return false;
      if (!mounted) return true;
      setState(() {
        _currentScenarioId = scenarioId;
        _currentScenarioName = scenarioName;
      });
      AppLogger.info('Macro steps persisted in scenario "$scenarioName".', name: 'macro');
      return true;
    } catch (error, stackTrace) {
      AppLogger.error(
        'Automatic macro persistence failed.',
        error: error,
        stackTrace: stackTrace,
        name: 'macro',
      );
      return false;
    }
  }

  Future<void> _cancelMacroRecording() async {
    if (!_macroRecording || _macroBusy) return;
    setState(() => _macroBusy = true);
    try {
      AppLogger.info('Cancelling macro recording.', name: 'macro');
      await _nativeAutomation.cancelMacroRecording();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Native macro cancellation failed; resetting UI state.',
        error: error,
        stackTrace: stackTrace,
        name: 'macro',
      );
    } finally {
      if (mounted) {
        setState(() {
          _macroRecording = false;
          _macroBusy = false;
          _macroEventCount = 0;
        });
      }
    }
  }

  void _handleError(String message, {Exception? exception}) {
    if (!mounted) return;

    _logDebug('Error: $message${exception != null ? '\nException: $exception' : ''}');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('❌ حدث خطأ', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(message, style: const TextStyle(fontSize: 13)),
            if (exception != null)
              Text(
                exception.toString().length > 80
                    ? '${exception.toString().substring(0, 80)}...'
                    : exception.toString(),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ==================== دوال الانتظار ====================
  Future<void> _wait(int ms) async {
    if (ms <= 0 || !_running || _stopRequested) return;
    await _executor.wait(ms);
  }

  List<AutomationStep> _cloneSteps(List<AutomationStep> source) {
    return source.map((step) => step.copy(id: _newId())).toList();
  }

  // ==================== دورة حياة التطبيق ====================
  @override
  void initState() {
    _executor = AutomationExecutor(
      isRunning: () => _running && !_stopRequested,
      maxRetries: () => _maxRetries,
      fastMode: () => _useFastMode,
    );
    super.initState();
    _loadAppSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshOpenWindowsList();
    });
    _windowsRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _refreshOpenWindowsList();
      }
    });
  }

  @override
  void dispose() {
    _running = false;
    _stopRequested = true;
    if (_macroRecording) {
      unawaited(_nativeAutomation.cancelMacroRecording());
    }
    _windowsRefreshTimer?.cancel();
    _stepsScrollController.dispose();
    _delayTimer?.cancel();
    if (_pendingDelay != null && !_pendingDelay!.isCompleted) {
      _pendingDelay!.complete();
    }
    super.dispose();
  }

  // ==================== دوال PowerShell ====================
  String _encodePowerShellCommand(String command) {
    final bytes = <int>[];
    for (final codeUnit in command.codeUnits) {
      bytes.add(codeUnit & 0xff);
      bytes.add((codeUnit >> 8) & 0xff);
    }
    return base64Encode(Uint8List.fromList(bytes));
  }

  // ==================== تحديث قائمة النوافذ ====================
  Future<void> _refreshOpenWindowsList() async {
    if (!mounted || _refreshingWindows) return;
    _refreshingWindows = true;
    try {
      await _refreshOpenWindowsListImpl();
    } finally {
      _refreshingWindows = false;
    }
  }

  Future<void> _refreshOpenWindowsListImpl() async {
    if (!mounted) return;

    // Prefer the native Win32 channel. It avoids starting PowerShell every
    // five seconds and keeps Unicode window titles inside the native boundary.
    try {
      final raw = await _nativeAutomation.invokeWindows<dynamic>('getOpenWindows');
      final windows = <Map<String, String>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final title = map['title']?.toString().trim() ?? '';
          final process = map['process']?.toString().trim() ?? '';
          if (title.isNotEmpty) {
            windows.add({'title': title, 'process': process});
          }
        }
      }
      windows.sort((a, b) => (a['title'] ?? '').compareTo(b['title'] ?? ''));
      if (!mounted) return;
      final selectionStillValid = _selectedWindowForDropdown == null ||
          windows.any((w) => w['title'] == _selectedWindowForDropdown);
      if (!_windowsListsEqual(_openWindows, windows) || !selectionStillValid) {
        setState(() {
          _openWindows = windows;
          if (!selectionStillValid) _selectedWindowForDropdown = null;
        });
      }
      return;
    } on MissingPluginException catch (error, stackTrace) {
      AppLogger.warning(
        'Native window channel is unavailable; falling back to PowerShell.',
        error: error,
        stackTrace: stackTrace,
        name: 'windows',
      );
    } on PlatformException catch (error, stackTrace) {
      AppLogger.warning(
        'Native window enumeration failed; falling back to PowerShell.',
        error: error,
        stackTrace: stackTrace,
        name: 'windows',
      );
    }

    // Compatibility fallback for older Windows runners.
    try {
      final command = r'''$ErrorActionPreference = 'Continue'
Get-Process | Where-Object {
  $_.MainWindowTitle -and
  $_.MainWindowTitle.Trim().Length -gt 0
} | ForEach-Object {
  try {
    $title = $_.MainWindowTitle -replace '[\r\n]', ''
    $title64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($title))
    $process64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_.ProcessName))
    Write-Output ($title64 + '|' + $process64)
  } catch {}
}''';
      final processResult = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-EncodedCommand',
          _encodePowerShellCommand(command),
        ],
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(
        const Duration(seconds: 4),
        onTimeout: () => ProcessResult(0, 1, '', 'timeout'),
      );

      final windows = <Map<String, String>>[];
      if (processResult.exitCode == 0) {
        for (final line in processResult.stdout.toString().split(RegExp(r'\r?\n'))) {
          final value = line.trim();
          if (value.isEmpty) continue;

          final separator = value.indexOf('|');
          if (separator <= 0) continue;

          try {
            final title = utf8.decode(
              base64Decode(value.substring(0, separator)),
              allowMalformed: true,
            ).trim();
            final process = utf8.decode(
              base64Decode(value.substring(separator + 1)),
              allowMalformed: true,
            ).trim();

            if (title.isNotEmpty) {
              windows.add({
                'title': title,
                'process': process,
              });
            }
          } catch (_) {}
        }
      }

      windows.sort((a, b) => (a['title'] ?? '').compareTo(b['title'] ?? ''));

      if (!mounted) return;
      final selectionStillValid = _selectedWindowForDropdown == null ||
          windows.any((w) => w['title'] == _selectedWindowForDropdown);
      if (_windowsListsEqual(_openWindows, windows) && selectionStillValid) {
        return;
      }
      setState(() {
        _openWindows = windows;
        if (!selectionStillValid) {
          _selectedWindowForDropdown = null;
        }
      });
    } catch (e, stackTrace) {
      AppLogger.warning('Window refresh fallback failed.', error: e, stackTrace: stackTrace, name: 'windows');
      if (!mounted) return;
      if (_openWindows.isEmpty && _selectedWindowForDropdown == null) return;
      setState(() {
        _openWindows = [];
        _selectedWindowForDropdown = null;
      });
    }
  }

  bool _windowsListsEqual(
      List<Map<String, String>> a, List<Map<String, String>> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i]['title'] != b[i]['title'] || a[i]['process'] != b[i]['process']) {
        return false;
      }
    }
    return true;
  }

  // ==================== معالجة النصوص والعدادات ====================
  Future<String> _processText(String text) async {
    String processed = text;
    final now = DateTime.now();
    if (processed.contains('{{date}}')) {
      processed = processed.replaceAll(
          '{{date}}', '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    }
    if (processed.contains('{{time}}')) {
      processed = processed.replaceAll(
          '{{time}}', '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}');
    }
    final regex = RegExp(r'{{counter([^}]*)}}');
    final matches = regex.allMatches(processed);
    for (final match in matches) {
      final counterName = match.group(1)?.trim() ?? '';
      final fullMatch = match.group(0)!;
      final key = 'counter_$counterName';
      if (!_counterValues.containsKey(key)) {
        _counterValues[key] = _counterStarts[key] ?? 1;
        _counterStarts[key] = _counterStarts[key] ?? 1;
      }
      final currentValue = _counterValues[key]!;
      processed = processed.replaceFirst(fullMatch, currentValue.toString());
      _counterValues[key] = currentValue + 1;
    }
    if (processed.contains('{{clipboard}}')) {
      try {
        final clipboardContent = await _nativeAutomation.invokeAutomation('get_clipboard');
        if (clipboardContent != null && clipboardContent is String) {
          processed = processed.replaceAll('{{clipboard}}', clipboardContent);
        }
      } catch (e) {
        _logDebug('Clipboard error: $e');
      }
    }
    return processed;
  }

  // ==================== دوال النوافذ ====================
  String _meaningfulWindowTitle(String value) {
    final open = value.lastIndexOf('[');
    final close = value.lastIndexOf(']');
    if (open >= 0 && close > open) {
      final fragment = value.substring(open + 1, close).trim();
      if (fragment.length >= 3) return fragment;
    }
    return value.trim();
  }

  bool _windowTitlesMatch(String requested, String actual) {
    final requestedTitle = _meaningfulWindowTitle(requested).toLowerCase();
    final actualTitle = actual.trim().toLowerCase();
    if (requestedTitle.isEmpty || actualTitle.isEmpty) return false;
    return requestedTitle == actualTitle ||
        actualTitle.contains(requestedTitle) ||
        requestedTitle.contains(actualTitle);
  }

  String _expectedProcessForWindowTitle(String title) {
    final value = title.toLowerCase();
    if (value.contains('google chrome') || value.contains('chrome')) return 'chrome.exe';
    if (value.contains('microsoft edge') || value.contains('edge')) return 'msedge.exe';
    if (value.contains('firefox')) return 'firefox.exe';
    if (value.contains('brave')) return 'brave.exe';
    return '';
  }

  bool _activeWindowMatches(String requestedTitle, String activeTitle, String activeProcess) {
    if (_windowTitlesMatch(requestedTitle, activeTitle)) return true;
    final expectedProcess = _expectedProcessForWindowTitle(requestedTitle);
    if (expectedProcess.isEmpty) return false;
    return activeProcess.trim().toLowerCase() == expectedProcess;
  }

  Future<bool> _isActiveWindowExpected(String windowTitle) async {
    try {
      final active = await _nativeAutomation.invokeWindows<dynamic>('getActiveWindow');
      if (active is Map) {
        final activeTitle = active['title']?.toString() ?? '';
        final activeProcess = active['process']?.toString() ?? '';
        return _activeWindowMatches(windowTitle, activeTitle, activeProcess);
      }
    } on PlatformException catch (error, stackTrace) {
      AppLogger.warning(
        'Active-window verification failed for "$windowTitle".',
        error: error,
        stackTrace: stackTrace,
        name: 'windows',
      );
    } on MissingPluginException {
      // Older runners do not expose active-window inspection. The activation
      // call remains the compatibility fallback in that case.
      return true;
    }
    return false;
  }

  Future<bool> _waitForActiveWindow(String windowTitle, {int timeoutMs = 3000}) async {
    final safeTimeout = timeoutMs.clamp(250, 10000).toInt();
    final endTime = DateTime.now().add(Duration(milliseconds: safeTimeout));
    do {
      if (!_running) return false;
      if (await _isActiveWindowExpected(windowTitle)) return true;
      final remaining = endTime.difference(DateTime.now()).inMilliseconds;
      if (remaining > 0) await _wait(min(120, remaining));
    } while (_running && DateTime.now().isBefore(endTime));
    return false;
  }

  Future<bool> _activateAndVerifyWindow(String windowTitle) async {
    final title = windowTitle.trim();
    if (title.isEmpty) return false;

    try {
      final activated = await _nativeAutomation
          .invokeWindows<bool>('activateWindow', {'windowTitle': title})
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          );
      if (activated != true) return false;

      // Give Windows a short interval to complete the foreground transition.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      try {
        final active = await _nativeAutomation.invokeWindows<dynamic>('getActiveWindow');
        if (active is Map) {
          final activeTitle = active['title']?.toString().trim() ?? '';
          final activeProcess = active['process']?.toString().trim() ?? '';
          if (activeTitle.isNotEmpty || activeProcess.isNotEmpty) {
            return _activeWindowMatches(title, activeTitle, activeProcess);
          }
          // A supported runner returned an empty active-window payload; do
          // not send input because the foreground target is unknown.
          return false;
        }
        return false;
      } on PlatformException {
        // The activation result is still valid when active-window inspection is unavailable.
      } on MissingPluginException {
        // Keep compatibility with older runners that do not expose getActiveWindow.
      }
      return true;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Window activation failed for "$title".',
        error: error,
        stackTrace: stackTrace,
        name: 'windows',
      );
      return false;
    }
  }

  Future<bool> _waitForWindow(String windowTitle, {int timeoutMs = 5000}) async {
    final safeTimeout = timeoutMs.clamp(100, 30000).toInt();
    final endTime = DateTime.now().add(Duration(milliseconds: safeTimeout));
    final minimumAttempts = (safeTimeout / 250).ceil();
    final maxAttempts = max(1, max(_maxRetries, minimumAttempts));
    var attempts = 0;
    while (_running && DateTime.now().isBefore(endTime) && attempts < maxAttempts) {
      if (await _activateAndVerifyWindow(windowTitle)) return true;
      attempts++;
      final remaining = endTime.difference(DateTime.now()).inMilliseconds;
      if (remaining > 0) {
        await _wait(min(250, remaining));
      }
    }
    return false;
  }

  Future<void> _invokeWithRetry(
    String method,
    Map<String, dynamic> arguments, {
    required String action,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _executor.invokeWithRetry(
      action: action,
      timeout: timeout,
      operation: () => _nativeAutomation.invokeAutomation<dynamic>(
        method,
        arguments,
      ),
    );
  }

  List<Map<String, String>> _uniqueOpenWindows() {
    final unique = <String, Map<String, String>>{};
    for (final window in _openWindows) {
      final title = window['title'] ?? '';
      if (title.isNotEmpty) unique.putIfAbsent(title, () => window);
    }
    return unique.values.toList();
  }

  String _inheritedTargetWindowForNewStep() {
    for (final step in _steps.reversed) {