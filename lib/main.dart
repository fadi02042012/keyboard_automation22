import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
    if (ms <= 0 || !_running) return;
    final completer = Completer<void>();
    _pendingDelay = completer;
    _delayTimer?.cancel();
    _delayTimer = Timer(Duration(milliseconds: ms), () {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await completer.future;
    } catch (e) {
      // تجاهل الأخطاء عند الإلغاء
    } finally {
      if (identical(_pendingDelay, completer)) _pendingDelay = null;
    }
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
      if (a[i]['title'] != b[i]['title'] ||
          a[i]['process'] != b[i]['process'] ||
          a[i]['hwnd'] != b[i]['hwnd']) {
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

  bool _activeWindowMatches(String requestedTitle, String activeTitle, String activeProcess) {
    // Process name is not a unique window identity (Chrome/Edge may have
    // several windows in the same process). Verification must therefore use
    // the actual title; native activation preserves the HWND affinity.
    return _windowTitlesMatch(requestedTitle, activeTitle);
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

  Future<bool> _activateAndVerifyWindow(String windowTitle, {String windowAlias = '', String windowMatch = 'title'}) async {
    final title = windowTitle.trim();
    final alias = windowAlias.trim();
    if (title.isEmpty && alias.isEmpty) return false;

    try {
      final activated = await _nativeAutomation
          .invokeWindows<bool>('activateWindow', {
            if (title.isNotEmpty) 'windowTitle': title,
            if (alias.isNotEmpty) 'windowAlias': alias,
          })
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
            return alias.isNotEmpty ? true : _activeWindowMatches(title, activeTitle, activeProcess);
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

  Future<bool> _waitForWindow(String windowTitle, {String windowAlias = '', String windowMatch = 'title', int timeoutMs = 5000}) async {
    final safeTimeout = timeoutMs.clamp(100, 30000).toInt();
    final endTime = DateTime.now().add(Duration(milliseconds: safeTimeout));
    final minimumAttempts = (safeTimeout / 250).ceil();
    final maxAttempts = max(1, max(_maxRetries, minimumAttempts));
    var attempts = 0;
    while (_running && DateTime.now().isBefore(endTime) && attempts < maxAttempts) {
      if (await _activateAndVerifyWindow(windowTitle, windowAlias: windowAlias, windowMatch: windowMatch)) return true;
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

  String _windowIdForTitle(String title) {
    final normalized = title.trim();
    if (normalized.isEmpty) return '';
    for (final window in _openWindows) {
      if ((window['title'] ?? '').trim() == normalized) {
        return window['hwnd']?.trim() ?? '';
      }
    }
    return '';
  }

  String _windowIdentityForSelection(
    String selectedWindow,
    String matchMode,
    String explicitAlias,
  ) {
    final alias = explicitAlias.trim();
    if (alias.isNotEmpty) return alias;
    if (matchMode == 'process') return selectedWindow;
    return _windowIdForTitle(selectedWindow);
  }

  String _inheritedTargetWindowForNewStep() {
    for (final step in _steps.reversed) {
      final target = step.targetWindow.trim();
      if (target.isNotEmpty) return target;
    }
    return _selectedWindowForDropdown?.trim() ?? '';
  }

  // ==================== واجهة اختيار النافذة ====================
  Future<String?> _showSelectWindowDialog() async {
    if (!mounted) return null;

    final windows = _openWindows;

    if (windows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ تعذر قراءة النوافذ المفتوحة. تأكد من تشغيل التطبيق بصلاحيات المسؤول (Admin).'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    }

    String searchQuery = '';
    String? selectedWindow = _inheritedTargetWindowForNewStep();
    bool windowChosen = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredWindows = windows.where((win) {
              final title = win['title']?.toLowerCase() ?? '';
              final process = win['process']?.toLowerCase() ?? '';
              final query = searchQuery.toLowerCase();
              return title.contains(query) || process.contains(query);
            }).toList();

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.window, color: Colors.indigo),
                  const SizedBox(width: 8),
                  const Text('اختر النافذة المستهدفة'),
                ],
              ),
              content: SizedBox(
                width: 500,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'ابحث عن نافذة...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          searchQuery = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredWindows.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.window, size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  Text('لا توجد نوافذ تطابق البحث',
                                      style: TextStyle(color: Colors.grey.shade600)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredWindows.length,
                              itemBuilder: (context, index) {
                                final win = filteredWindows[index];
                                final title = win['title'] ?? 'بدون عنوان';
                                final process = win['process'] ?? '';
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 2),
                                  elevation: 0,
                                  color: Colors.grey.shade50,
                                  child: ListTile(
                                    leading: const Icon(Icons.window, color: Colors.grey),
                                    title: Text(
                                      title,
                                      style: const TextStyle(fontWeight: FontWeight.normal),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      process,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    onTap: () {
                                      selectedWindow = title;
                                      windowChosen = true;
                                      Navigator.pop(context);
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${windows.length} نافذة مفتوحة',
                              style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        );
      },
    );

    return windowChosen ? selectedWindow : null;
  }

  // ==================== دوال إضافة الخطوات ====================
  Future<void> _addWaitForWindow() async {
    if (!mounted) return;

    String selectedWindow = await _showSelectWindowDialog() ?? '';
    if (!mounted) return;
    if (selectedWindow.isEmpty) return;

    String windowMatch = 'title';
    final windowAliasController = TextEditingController();
    final timeoutController = TextEditingController(text: '5000');

    final timeoutResult = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) timeoutController.dispose();
          },
          child: AlertDialog(
            title: const Text('مدة انتظار النافذة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'المدة الزمنية القصوى لانتظار النافذة بالمللي ثانية',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timeoutController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'المهلة (مللي ثانية)',
                    hintText: '5000',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  final timeout = int.tryParse(timeoutController.text) ?? 5000;
                  Navigator.pop(context, timeout.clamp(1000, 30000).toInt());
                },
                child: const Text('حفظ'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (timeoutResult == null) return;
    _captureEditorChange();
    final windowAlias = _windowIdentityForSelection(
      selectedWindow,
      windowMatch,
      windowAliasController.text,
    );
    windowAliasController.dispose();
    setState(() {
      _steps.add(AutomationStep(
        id: _newId(),
        type: StepType.waitForWindow,
        targetWindow: selectedWindow,
        windowAlias: windowAlias,
        windowMatch: windowMatch,
        waitTimeoutMs: timeoutResult,
      ));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ تم إضافة شرط انتظار النافذة: "$selectedWindow"'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==================== دوال إعدادات التطبيق ====================
  Future<void> _loadAppSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _randomDelayEnabled = prefs.getBool('settings.randomDelayEnabled') ?? _randomDelayEnabled;
        _randomDelayMin = (prefs.getInt('settings.randomDelayMin') ?? _randomDelayMin).clamp(0, 10000);
        _randomDelayMax = (prefs.getInt('settings.randomDelayMax') ?? _randomDelayMax).clamp(_randomDelayMin, 10000);
        _scenarioIntervalMs = (prefs.getInt('settings.scenarioIntervalMs') ?? _scenarioIntervalMs).clamp(0, 3600000);
        _maxRetries = (prefs.getInt('settings.maxRetries') ?? _maxRetries).clamp(1, 10);
        _useFastMode = prefs.getBool('settings.useFastMode') ?? _useFastMode;
        _debugMode = prefs.getBool('settings.debugMode') ?? _debugMode;
      });
      AppLogger.debugEnabled = _debugMode;
      AppLogger.info('Application settings loaded.', name: 'settings');
    } catch (error, stackTrace) {
      AppLogger.warning('Could not load application settings; defaults remain active.', error: error, stackTrace: stackTrace, name: 'settings');
    }
  }

  Future<void> _persistAppSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setBool('settings.randomDelayEnabled', _randomDelayEnabled),
        prefs.setInt('settings.randomDelayMin', _randomDelayMin),
        prefs.setInt('settings.randomDelayMax', _randomDelayMax),
        prefs.setInt('settings.scenarioIntervalMs', _scenarioIntervalMs),
        prefs.setInt('settings.maxRetries', _maxRetries),
        prefs.setBool('settings.useFastMode', _useFastMode),
        prefs.setBool('settings.debugMode', _debugMode),
      ]);
      AppLogger.debug('Application settings persisted.', name: 'settings');
    } catch (error, stackTrace) {
      AppLogger.warning('Could not persist application settings.', error: error, stackTrace: stackTrace, name: 'settings');
    }
  }

  // ==================== دوال حفظ وتحميل السيناريوهات ====================
  Future<List<Scenario>> _loadScenarios() async {
    try {
      return await _scenarioStorage.load();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Load scenarios failed; returning an empty list.',
        error: error,
        stackTrace: stackTrace,
        name: 'storage',
      );
      return [];
    }
  }

  Future<bool> _persistScenarios(List<Scenario> scenarios) async {
    try {
      await _scenarioStorage.save(scenarios);
      return true;
    } catch (error, stackTrace) {
      AppLogger.error(
        'Persist scenarios failed.',
        error: error,
        stackTrace: stackTrace,
        name: 'storage',
      );
      if (mounted) {
        _handleError('فشل حفظ السيناريوهات', exception: Exception(error));
      }
      return false;
    }
  }

  Future<void> _newScenario() async {
    _editorController.clear();
    setState(() {
      _steps.clear();
      _currentScenarioName = 'اكتب اسم';
      _currentScenarioId = null;
      _loopRangeStart = null;
      _loopRangeEnd = null;
      _selectedRepeatSteps.clear();
      _counterValues.clear();
      _counterStarts.clear();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إنشاء سيناريو جديد فارغ'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _saveCurrentScenario() async {
    if (_currentScenarioId == null) {
      await _saveScenarioAsNew();
      return;
    }
    final scenarios = await _loadScenarios();
    if (scenarios.isEmpty) {
      await _saveScenarioAsNew();
      return;
    }
    final index = scenarios.indexWhere((s) => s.id == _currentScenarioId);
    if (index == -1) {
      await _saveScenarioAsNew();
      return;
    }
    final updatedScenario = Scenario(
      id: _currentScenarioId!,
      name: _currentScenarioName,
      steps: _cloneSteps(_steps),
    );
    scenarios[index] = updatedScenario;
    await _persistScenarios(scenarios);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم تحديث السيناريو "$_currentScenarioName" بنجاح'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _saveScenarioAsNew() async {
    if (!mounted) return;
    final nameController = TextEditingController(text: _currentScenarioName);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) nameController.dispose();
          },
          child: AlertDialog(
            title: const Text('حفظ السيناريو باسم'),
            content: TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'اسم السيناريو', border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  Navigator.pop(context, name.isNotEmpty ? name : null);
                },
                child: const Text('حفظ'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, null);
                },
                child: const Text('إلغاء'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (result == null || result.isEmpty) return;
    final name = result;
    final scenarios = await _loadScenarios();
    if (!mounted) return;
    final existingIndex = scenarios.indexWhere((s) => s.name == name);
    if (existingIndex != -1) {
      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return PopScope(
            canPop: true,
            onPopInvokedWithResult: (didPop, result) {},
            child: AlertDialog(
              title: const Text('سيناريو موجود'),
              content: Text('هل تريد استبدال السيناريو "$name"؟'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('استبدال')),
              ],
            ),
          );
        },
      );
      if (!mounted) return;
      if (confirm != true) return;
      scenarios.removeAt(existingIndex);
    }
    final scenario = Scenario(id: _newId(), name: name, steps: _cloneSteps(_steps));
    scenarios.add(scenario);
    await _persistScenarios(scenarios);
    if (!mounted) return;
    setState(() {
      _currentScenarioName = name;
      _currentScenarioId = scenario.id;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ السيناريو "$name" بنجاح'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _loadScenario() async {
    if (!mounted) return;
    try {
      final scenarios = await _loadScenarios();
      if (!mounted) return;
      if (scenarios.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد سيناريوهات محفوظة'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      String? selectedId = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return PopScope(
            canPop: true,
            onPopInvokedWithResult: (didPop, result) {},
            child: AlertDialog(
              title: const Text('فتح سيناريو'),
              content: SizedBox(
                width: 300,
                height: 300,
                child: ListView.builder(
                  itemCount: scenarios.length,
                  itemBuilder: (context, index) {
                    final scenario = scenarios[index];
                    return ListTile(
                      title: Text(scenario.name),
                      subtitle: Text('${scenario.steps.length} خطوات'),
                      leading: const Icon(Icons.folder),
                      onTap: () => Navigator.pop(context, scenario.id),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) {
                              return PopScope(
                                canPop: true,
                                onPopInvokedWithResult: (didPop, result) {},
                                child: AlertDialog(
                                  title: const Text('حذف السيناريو'),
                                  content: Text('هل تريد حذف "${scenario.name}"؟'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
                                  ],
                                ),
                              );
                            },
                          );
                          if (confirm == true) {
                            scenarios.removeAt(index);
                            await _persistScenarios(scenarios);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            unawaited(_loadScenario());
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('إلغاء')),
              ],
            ),
          );
        },
      );
      if (!mounted) return;
      if (selectedId == null) return;
      final selectedScenario = scenarios.firstWhere(
        (s) => s.id == selectedId,
        orElse: () => scenarios.first,
      );
      if (mounted) {
        _editorController.clear();
        setState(() {
          _steps.clear();
          _steps.addAll(_cloneSteps(selectedScenario.steps));
          _currentScenarioName = selectedScenario.name;
          _currentScenarioId = selectedScenario.id;
          _loopRangeStart = null;
          _loopRangeEnd = null;
          _selectedRepeatSteps.clear();
          _counterValues.clear();
          _counterStarts.clear();
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم فتح "${selectedScenario.name}"'), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      _handleError('خطأ في تحميل السيناريو', exception: Exception(e));
    }
  }

  // ==================== دوال تصدير واستيراد ====================
  Future<void> _exportScenario() async {
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد خطوات لتصديرها')),
      );
      return;
    }

    try {
      final scenario = Scenario(
        id: _currentScenarioId ?? 'export-${DateTime.now().microsecondsSinceEpoch}',
        name: _currentScenarioName.trim().isEmpty ? 'سيناريو' : _currentScenarioName.trim(),
        steps: _steps.map((step) => step.copy()).toList(),
      );
      final bytes = _scenarioFileService.encodeScenario(
        scenario: scenario,
        appVersion: kAppVersion,
      );
      final outputUri = await FilePicker.saveFile(
        dialogTitle: 'حفظ السيناريو',
        fileName: '${scenario.name}_backup.json',
        bytes: bytes,
        mimeType: 'application/json',
        allowedExtensions: ['json'],
      );
      if (outputUri != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير ${scenario.steps.length} خطوة بنجاح إلى:\n${outputUri.toFilePath()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'Scenario export failed',
        error: error,
        stackTrace: stackTrace,
      );
      _handleError('فشل التصدير: $error', exception: Exception(error));
    }
  }

  Future<void> _importScenario() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'اختر ملف السيناريو',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final filePath = files.isEmpty ? null : files.first.path;
      if (filePath == null) return;

      final imported = _scenarioFileService.decodeScenario(
        await File(filePath).readAsString(),
      );
      if (!mounted) return;

      final shouldReplace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تأكيد استيراد السيناريو'),
          content: Text(
            'السيناريو: ${imported.name}\n'
            'عدد الخطوات: ${imported.steps.length}\n\n'
            'سيتم استبدال الخطوات الحالية. هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('استيراد'),
            ),
          ],
        ),
      );
      if (shouldReplace != true || !mounted) return;

      final newSteps = imported.steps.map((step) => step.copy(id: _newId())).toList();
      _captureEditorChange();
      setState(() {
        _steps
          ..clear()
          ..addAll(newSteps);
        _currentScenarioName = imported.name;
        _currentScenarioId = null;
        _loopRangeStart = null;
        _loopRangeEnd = null;
        _selectedRepeatSteps.clear();
        // Imported steps may contain counters from another scenario. Reset the
        // runtime state so the imported scenario starts from its definitions.
        _counterValues.clear();
        _counterStarts.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم استيراد ${newSteps.length} خطوة بنجاح'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FormatException catch (error, stackTrace) {
      AppLogger.warning(
        'Invalid scenario import: $error',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _handleError('فشل الاستيراد: $error', exception: error);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Scenario import failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _handleError('فشل الاستيراد: $error', exception: Exception(error));
    }
  }

  Future<void> _renameScenario() async {
    if (_currentScenarioId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد سيناريو محمل لتعديل اسمه'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final scenarios = await _loadScenarios();
    if (!mounted) return;
    final index = scenarios.indexWhere((s) => s.id == _currentScenarioId);
    if (index == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('السيناريو غير موجود'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final currentName = scenarios[index].name;
    final nameController = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) nameController.dispose();
          },
          child: AlertDialog(
            title: const Text('تعديل اسم السيناريو'),
            content: TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'الاسم الجديد', border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  Navigator.pop(context, name.isNotEmpty ? name : null);
                },
                child: const Text('حفظ'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, null);
                },
                child: const Text('إلغاء'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (newName == null || newName.isEmpty || newName == currentName) return;
    final existing = scenarios.indexWhere((s) => s.name == newName && s.id != _currentScenarioId);
    if (existing != -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يوجد سيناريو بهذا الاسم بالفعل'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    scenarios[index].name = newName;
    await _persistScenarios(scenarios);
    if (mounted) {
      setState(() {
        _currentScenarioName = newName;
      });
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم تعديل الاسم إلى "$newName"'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _deleteCurrentScenario() async {
    if (_currentScenarioId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد سيناريو محمل لحذفه'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {},
          child: AlertDialog(
            title: const Text('حذف السيناريو'),
            content: Text('هل تريد حذف السيناريو "$_currentScenarioName"؟'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (confirm != true) return;
    final scenarios = await _loadScenarios();
    scenarios.removeWhere((s) => s.id == _currentScenarioId);
    await _persistScenarios(scenarios);
    if (mounted) {
      _editorController.clear();
      setState(() {
        _steps.clear();
        _currentScenarioName = 'اكتب اسم';
        _currentScenarioId = null;
        _loopRangeStart = null;
        _loopRangeEnd = null;
        _selectedRepeatSteps.clear();
      });
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف السيناريو'), behavior: SnackBarBehavior.floating),
    );
  }

  // ==================== دوال الإعدادات ====================
  void _showRandomDelaySettings() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        int minVal = _randomDelayMin;
        int maxVal = _randomDelayMax;
        bool enabled = _randomDelayEnabled;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, result) {},
              child: AlertDialog(
                title: const Text('تأخير عشوائي بين الخطوات'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('تفعيل التأخير العشوائي'),
                      value: enabled,
                      onChanged: (val) {
                        setDialogState(() {
                          enabled = val;
                        });
                      },
                    ),
                    if (enabled) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'الحد الأدنى (مللي ثانية)', border: OutlineInputBorder()),
                              onChanged: (val) {
                                final v = int.tryParse(val);
                                if (v != null) minVal = v;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'الحد الأقصى (مللي ثانية)', border: OutlineInputBorder()),
                              onChanged: (val) {
                                final v = int.tryParse(val);
                                if (v != null) maxVal = v;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (mounted) {
                        setState(() {
                          _randomDelayEnabled = enabled;
                          if (enabled) {
                            _randomDelayMin = minVal.clamp(0, maxVal).toInt();
                            _randomDelayMax = maxVal.clamp(minVal, 10000).toInt();
                          }
                        });
                        _persistAppSettings();
                      }
                      Navigator.pop(context);
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showPerformanceSettings() async {
    if (!mounted) return;
    final retriesController = TextEditingController(text: '$_maxRetries');
    final intervalController = TextEditingController(text: '$_scenarioIntervalMs');
    var debugEnabled = _debugMode;
    var fastModeEnabled = _useFastMode;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('إعدادات الأداء والتشخيص'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: retriesController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'عدد محاولات إعادة التنفيذ',
                          helperText: 'من 1 إلى 10 محاولات',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: intervalController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الفاصل الدوري الافتراضي (مللي ثانية)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('الوضع السريع'),
                        subtitle: const Text('تقليل تأخير إعادة المحاولة الداخلية'),
                        value: fastModeEnabled,
                        onChanged: (value) => setDialogState(() => fastModeEnabled = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('تسجيل التشخيص'),
                        subtitle: const Text('يساعد في تحليل أخطاء التشغيل'),
                        value: debugEnabled,
                        onChanged: (value) => setDialogState(() => debugEnabled = value),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final retries = int.tryParse(retriesController.text.trim());
                      final interval = int.tryParse(intervalController.text.trim());
                      if (retries == null || interval == null || retries < 1 || interval < 0) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('أدخل قيماً صحيحة للإعدادات.')),
                        );
                        return;
                      }
                      setState(() {
                        _maxRetries = retries.clamp(1, 10).toInt();
                        _scenarioIntervalMs = interval.clamp(0, 3600000).toInt();
                        _debugMode = debugEnabled;
                        _useFastMode = fastModeEnabled;
                        AppLogger.debugEnabled = debugEnabled;
                      });
                      AppLogger.info('Performance settings updated.', name: 'settings');
                      await _persistAppSettings();
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      retriesController.dispose();
      intervalController.dispose();
    }
  }

  void _syncCounterDefinitionsFromSteps() {
    for (final step in _steps) {
      if (step.type == StepType.setCounter && step.counterName.trim().isNotEmpty) {
        final key = 'counter_${step.counterName.trim()}';
        final value = step.counterValue;
        _counterStarts[key] = value;
        _counterValues.putIfAbsent(key, () => value);
      } else if (step.type == StepType.incrementCounter && step.counterName.trim().isNotEmpty) {
        final key = 'counter_${step.counterName.trim()}';
        _counterStarts.putIfAbsent(key, () => 1);
        _counterValues.putIfAbsent(key, () => 1);
      }
    }
  }

  Future<void> _showCounterManager() async {
    _syncCounterDefinitionsFromSteps();
    final nameController = TextEditingController();
    final valueController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void addCounterFromFields({bool refreshDialog = true}) {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final value = int.tryParse(valueController.text) ?? 1;
              final key = 'counter_$name';
              _counterStarts[key] = value;
              _counterValues[key] = value;
              if (refreshDialog) setDialogState(() {});
              nameController.clear();
              valueController.clear();
            }

            return AlertDialog(
              title: const Text('إدارة العدادات الديناميكية'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'الاسم (مثال: فرع, يوم, inv)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: valueController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'القيمة الابتدائية',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.indigo),
                          onPressed: addCounterFromFields,
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    if (_counterStarts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'لا توجد عدادات. أضف عداداً جديداً.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView(
                          shrinkWrap: true,
                          children: _counterStarts.entries.map((entry) {
                            final key = entry.key;
                            final startValue = entry.value;
                            final currentValue = _counterValues[key] ?? startValue;
                            final displayName = key.replaceFirst('counter_', '');
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.numbers, size: 18),
                              title: Text('{{counter$displayName}}'),
                              subtitle: Text(
                                  'يبدأ من $startValue  →  القيمة الحالية: $currentValue'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.refresh, size: 18),
                                    tooltip: 'إعادة تعيين إلى القيمة الابتدائية',
                                    onPressed: () {
                                      _counterValues[key] = startValue;
                                      setDialogState(() {});
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    onPressed: () {
                                      _counterStarts.remove(key);
                                      _counterValues.remove(key);
                                      setDialogState(() {});
                                    },
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    addCounterFromFields(refreshDialog: false);
                    Navigator.pop(context);
                    if (mounted) setState(() {});
                  },
                  child: const Text('حفظ وإغلاق'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    valueController.dispose();
  }

  void _addText() => _showEnhancedTextDialog();
  void _addKey() => _showKeyDialog();
  void _addDelay() => _showDelayDialog();
  void _addMouse() => _showMouseDialog();
  void _addSetCounter() => _showSetCounterDialog();
  void _addIncrementCounter() => _showIncrementCounterDialog();
  void _addShortcut() => _showShortcutDialog();
  void _addSemanticCommand() => _showSemanticCommandDialog();

  Future<void> _showSemanticCommandDialog({AutomationStep? existing, int? index}) async {
    final windowAliasController = TextEditingController(text: existing?.windowAlias ?? '');
    String selectedWindow = existing?.targetWindow ?? _selectedWindowForDropdown ?? '';
    final existingCommand = existing?.command.trim() ?? '';
    String command = existingCommand.isNotEmpty ? existingCommand : 'invoke';
    String windowMatch = existing?.windowMatch ?? 'title';
    final nameController = TextEditingController(text: existing?.commandArguments['name']?.toString() ?? '');
    final idController = TextEditingController(text: existing?.commandArguments['automationId']?.toString() ?? '');
    final classController = TextEditingController(text: existing?.commandArguments['className']?.toString() ?? '');
    final controlTypeController = TextEditingController(text: existing?.commandArguments['controlType']?.toString() ?? '');
    final valueController = TextEditingController(text: existing?.commandArguments['value']?.toString() ?? '');
    final delayController = TextEditingController(text: (existing?.delayMs ?? 200).toString());
    final timeoutController = TextEditingController(text: (existing?.waitTimeoutMs ?? 5000).toString());

    Future<void> inspect() async {
      if (selectedWindow.trim().isEmpty) return;
      try {
        final elements = await _nativeAutomation.inspectUiElements(windowTitle: selectedWindow);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('عناصر النافذة'),
            content: SizedBox(
              width: 700,
              height: 480,
              child: elements.isEmpty
                  ? const Center(child: Text('لم يتم العثور على عناصر.'))
                  : ListView.builder(
                      itemCount: elements.length,
                      itemBuilder: (context, i) {
                        final item = elements[i];
                        final title = item['name']?.toString() ?? '';
                        final id = item['automationId']?.toString() ?? '';
                        final className = item['className']?.toString() ?? '';
                        final type = item['controlType']?.toString() ?? '';
                        return ListTile(
                          dense: true,
                          title: Text(title.isEmpty ? '(بدون اسم)' : title),
                          subtitle: Text('AutomationId: $id | Class: $className | ControlType: $type'),
                          onTap: () {
                            nameController.text = title;
                            idController.text = id;
                            classController.text = className;
                            controlTypeController.text = type;
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
          ),
        );
      } on PlatformException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? 'تعذر فحص عناصر النافذة')));
        }
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'إضافة أمر دلالي' : 'تعديل أمر دلالي'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStepWindowSelector(
                    selectedWindow: selectedWindow,
                    initialMatch: windowMatch,
                    onChanged: (value) => setDialogState(() => selectedWindow = value ?? ''),
                    onMatchChanged: (value) => setDialogState(() => windowMatch = value ?? 'title'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: command,
                    decoration: const InputDecoration(labelText: 'الأمر الدلالي', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'invoke', child: Text('تنفيذ زر / Invoke')),
                      DropdownMenuItem(value: 'set_value', child: Text('تعيين قيمة حقل')),
                      DropdownMenuItem(value: 'toggle', child: Text('تبديل خيار')),
                      DropdownMenuItem(value: 'select', child: Text('اختيار عنصر')),
                      DropdownMenuItem(value: 'focus', child: Text('تركيز على عنصر')),
                      DropdownMenuItem(value: 'wait_for_element', child: Text('انتظار ظهور عنصر')),
                    ],
                    onChanged: (value) => setDialogState(() => command = value ?? 'invoke'),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'اسم العنصر UIA (اختياري)', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: idController, decoration: const InputDecoration(labelText: 'AutomationId (اختياري)', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: classController, decoration: const InputDecoration(labelText: 'ClassName (اختياري)', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: controlTypeController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ControlType الرقمي (اختياري)', border: OutlineInputBorder())),
                  if (command == 'set_value') ...[
                    const SizedBox(height: 10),
                    TextField(controller: valueController, decoration: const InputDecoration(labelText: 'القيمة الجديدة', border: OutlineInputBorder())),
                  ],
                  const SizedBox(height: 10),
                  TextField(controller: delayController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'التأخير بعد الأمر (مللي ثانية)', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: timeoutController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مهلة العثور على العنصر (مللي ثانية)', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(onPressed: selectedWindow.trim().isEmpty ? null : inspect, icon: const Icon(Icons.account_tree_outlined), label: const Text('فحص عناصر النافذة')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                final args = <String, dynamic>{};
                if (nameController.text.trim().isNotEmpty) args['name'] = nameController.text.trim();
                if (idController.text.trim().isNotEmpty) args['automationId'] = idController.text.trim();
                if (classController.text.trim().isNotEmpty) args['className'] = classController.text.trim();
                if (controlTypeController.text.trim().isNotEmpty) {
                  final controlType = int.tryParse(controlTypeController.text.trim());
                  if (controlType == null || controlType < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ControlType يجب أن يكون رقماً صحيحاً')));
                    return;
                  }
                  args['controlType'] = controlType.toString();
                }
                if (command == 'set_value') args['value'] = valueController.text;
                if (args['name'] == null && args['automationId'] == null && args['className'] == null && args['controlType'] == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل محدداً واحداً على الأقل للعنصر')));
                  return;
                }
                final step = AutomationStep(
                  id: existing?.id ?? _newId(),
                  type: StepType.semanticCommand,
                  targetWindow: selectedWindow.trim(),
                  windowAlias: _windowIdentityForSelection(
                    selectedWindow,
                    windowMatch,
                    windowAliasController.text,
                  ),
                  windowMatch: windowMatch,
                  command: command,
                  commandArguments: args,
                  delayMs: max(0, int.tryParse(delayController.text) ?? 200),
                  waitTimeoutMs: (int.tryParse(timeoutController.text) ?? 5000).clamp(100, 30000).toInt(),
                );
                _captureEditorChange();
                setState(() {
                  if (index == null) {
                    _steps.add(step);
                  } else {
                    _steps[index] = step;
                  }
                });
                Navigator.pop(context, true);
              },
              child: const Text('حفظ'),
            ),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ],
        ),
      ),
    );
    nameController.dispose();
    idController.dispose();
    classController.dispose();
    controlTypeController.dispose();
    valueController.dispose();
    delayController.dispose();
    timeoutController.dispose();
    windowAliasController.dispose();
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _addSavedScenario() async {
    if (!mounted) return;
    final scenarios = await _loadScenarios();
    if (!mounted) return;
    if (scenarios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سيناريوهات محفوظة لإدراجها'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    String? selectedId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: true,
          child: AlertDialog(
            title: const Text('اختر سيناريو للإدراج'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: ListView.builder(
                itemCount: scenarios.length,
                itemBuilder: (context, index) {
                  final scenario = scenarios[index];
                  return ListTile(
                    title: Text(scenario.name),
                    subtitle: Text('${scenario.steps.length} خطوات'),
                    leading: const Icon(Icons.folder),
                    onTap: () => Navigator.pop(context, scenario.id),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('إلغاء')),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (selectedId == null) return;
    final selectedScenario = scenarios.firstWhere(
      (s) => s.id == selectedId,
      orElse: () => scenarios.first,
    );
    final newSteps = _cloneSteps(selectedScenario.steps);
    if (mounted) {
      _captureEditorChange();
      setState(() {
        _steps.addAll(newSteps);
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إدراج "${selectedScenario.name}" (${newSteps.length} خطوات)'), behavior: SnackBarBehavior.floating),
    );
  }

  // ==================== واجهة إضافة النص ====================
  Widget _buildStepWindowSelector({
    required String selectedWindow,
    required ValueChanged<String?> onChanged,
    String initialMatch = 'title',
    ValueChanged<String?>? onMatchChanged,
  }) {
    final availableWindows = _uniqueOpenWindows();
    final matchMode = initialMatch == 'process' ? 'process' : 'title';
    final availableValues = availableWindows
        .map((window) => matchMode == 'process'
            ? (window['process'] ?? '').trim()
            : (window['title'] ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final value = availableValues.contains(selectedWindow) ? selectedWindow : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'النافذة المستهدفة لهذه الخطوة',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.window_outlined),
      ),
      hint: Text(
        _openWindows.isEmpty ? 'حدّث قائمة النوافذ أولاً' : 'اختر النافذة التي ستنفذ الخطوة',
        overflow: TextOverflow.ellipsis,
      ),
      items: () {
        final seen = <String>{};
        return availableWindows.map((window) {
          final title = (window['title'] ?? '').trim();
          final processName = (window['process'] ?? '').trim();
          final itemValue = matchMode == 'process' ? processName : title;
          if (itemValue.isEmpty || !seen.add(itemValue.toLowerCase())) return null;
          return DropdownMenuItem<String>(
          value: itemValue,
          child: Text(
            matchMode == 'process'
                ? processName
                : title + (processName.isNotEmpty ? ' [' + processName + ']' : ''),
            overflow: TextOverflow.ellipsis,
          ),
          );
        }).whereType<DropdownMenuItem<String>>().toList();
      }(),
      onChanged: _openWindows.isEmpty ? null : onChanged,
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(value: 'title', icon: Icon(Icons.window_outlined), label: Text('اسم النافذة')),
            ButtonSegment<String>(value: 'process', icon: Icon(Icons.apps_outlined), label: Text('اسم البرنامج')),
          ],
          selected: {matchMode},
          onSelectionChanged: onMatchChanged == null
              ? null
              : (selection) => onMatchChanged(selection.first),
        ),
      ],
    );
  }

  Widget _buildVarButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool isMenu = false,
  }) {
    return ActionChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
          if (isMenu) const Icon(Icons.arrow_drop_down, size: 14),
        ],
      ),
      onPressed: isMenu ? null : onPressed,
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(color: Colors.grey.shade300),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      labelStyle: const TextStyle(fontSize: 11),
    );
  }

  Widget _buildTemplateChip({
    required String label,
    required VoidCallback onPressed,
  }) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onPressed,
      backgroundColor: Colors.indigo.shade50,
      side: BorderSide(color: Colors.indigo.shade200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      labelStyle: TextStyle(fontSize: 11, color: Colors.indigo.shade700),
    );
  }

  Future<void> _showEnhancedTextDialog({AutomationStep? existing, int? index}) async {
    if (!mounted) return;
    _syncCounterDefinitionsFromSteps();

    final textController = TextEditingController(text: existing?.text ?? '');
    final repeatController = TextEditingController(text: '${existing?.repeat ?? 1}');
    final delayController = TextEditingController(text: '${existing?.delayMs ?? 0}');
    final windowAliasController = TextEditingController(text: existing?.windowAlias ?? '');
    String selectedWindow = existing?.targetWindow.isNotEmpty == true
        ? existing!.targetWindow
        : _inheritedTargetWindowForNewStep();
    String windowMatch = existing?.windowMatch ?? 'title';

    String previewText = textController.text;

    void updatePreview() {
      String processed = textController.text;
      final now = DateTime.now();

      processed = processed.replaceAll('{{date}}',
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
      processed = processed.replaceAll('{{time}}',
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}');

      final counterRegex = RegExp(r'{{counter([^}]*)}}');
      final matches = counterRegex.allMatches(processed);
      for (final match in matches) {
        final counterName = match.group(1)?.trim() ?? '';
        final key = 'counter_$counterName';
        final value = _counterValues[key] ?? _counterStarts[key] ?? 1;
        processed = processed.replaceFirst(match.group(0)!, value.toString());
      }

      processed = processed.replaceAll('{{clipboard}}', '[محتوى الحافظة]');

      setState(() {
        previewText = processed;
      });
    }

    void insertAtCursor(String insertText) {
      final current = textController.text;
      final cursor = textController.selection.baseOffset;
      final newText = current.substring(0, cursor) + insertText + current.substring(cursor);
      textController.text = newText;
      final newPos = cursor + insertText.length;
      textController.selection = TextSelection.collapsed(offset: newPos);
      updatePreview();
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) {
                  textController.dispose();
                  repeatController.dispose();
                  delayController.dispose();
                  windowAliasController.dispose();
                }
              },
              child: AlertDialog(
                title: Row(
                  children: [
                    Icon(existing == null ? Icons.post_add : Icons.edit_note,
                        color: Colors.blue),
                    const SizedBox(width: 10),
                    Text(existing == null ? '✏️ إضافة كتابة نص' : '📝 تعديل كتابة النص'),
                  ],
                ),
                content: SizedBox(
                  width: 620,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.only(start: 4),
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStepWindowSelector(
                        selectedWindow: selectedWindow,
                        initialMatch: windowMatch,
                        onChanged: (value) {
                          setDialogState(() => selectedWindow = value ?? '');
                        },
                        onMatchChanged: (value) {
                          setDialogState(() => windowMatch = value ?? 'title');
                        },
                      ),
                      const SizedBox(height: 10),

                      const Text('📝 المحتوى', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: textController,
                        autofocus: true,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'اكتب النص هنا...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        onChanged: (_) {
                          updatePreview();
                          setDialogState(() {});
                        },
                      ),

                      const SizedBox(height: 8),

                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildVarButton(
                            label: '📅 التاريخ',
                            icon: Icons.calendar_today,
                            onPressed: () {
                              insertAtCursor('{{date}}');
                              setDialogState(() {});
                            },
                          ),
                          _buildVarButton(
                            label: '🕐 الوقت',
                            icon: Icons.access_time,
                            onPressed: () {
                              insertAtCursor('{{time}}');
                              setDialogState(() {});
                            },
                          ),
                          _buildVarButton(
                            label: '📋 الحافظة',
                            icon: Icons.content_paste,
                            onPressed: () {
                              insertAtCursor('{{clipboard}}');
                              setDialogState(() {});
                            },
                          ),
                          PopupMenuButton<String>(
                            child: _buildVarButton(
                              label: '🔢 عداد',
                              icon: Icons.numbers,
                              onPressed: () {},
                              isMenu: true,
                            ),
                            onSelected: (value) async {
                              if (value == '___manage___') {
                                Navigator.pop(context);
                                await _showCounterManager();
                                if (mounted) {
                                  _showEnhancedTextDialog(existing: existing, index: index);
                                }
                                return;
                              }
                              insertAtCursor('{{counter$value}}');
                              setDialogState(() {});
                            },
                            itemBuilder: (context) {
                              final items = <PopupMenuItem<String>>[];
                              if (_counterStarts.isEmpty) {
                                items.add(
                                  const PopupMenuItem<String>(
                                    value: '',
                                    child: Text('⚠️ لا توجد عدادات'),
                                  ),
                                );
                              } else {
                                for (final entry in _counterStarts.entries) {
                                  final name = entry.key.replaceFirst('counter_', '');
                                  final currentVal = _counterValues[entry.key] ?? entry.value;
                                  items.add(
                                    PopupMenuItem<String>(
                                      value: name,
                                      child: Text('$name (القيمة: $currentVal)'),
                                    ),
                                  );
                                }
                              }
                              items.add(
                                const PopupMenuItem<String>(
                                  value: '___manage___',
                                  child: Row(
                                    children: [
                                      Icon(Icons.add, size: 16, color: Colors.indigo),
                                      SizedBox(width: 6),
                                      Text('إدارة العدادات...'),
                                    ],
                                  ),
                                ),
                              );
                              return items;
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      const Text('🎨 قوالب جاهزة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _buildTemplateChip(
                            label: '🏷️ عملية',
                            onPressed: () {
                              textController.text = 'عملية رقم {{counterعملية}} - {{date}}';
                              updatePreview();
                              setDialogState(() {});
                            },
                          ),
                          _buildTemplateChip(
                            label: '📋 تقرير',
                            onPressed: () {
                              textController.text = 'تقرير {{date}} الساعة {{time}}\nالمحتوى: {{clipboard}}';
                              updatePreview();
                              setDialogState(() {});
                            },
                          ),
                          _buildTemplateChip(
                            label: '📦 أمر',
                            onPressed: () {
                              textController.text = 'تنفيذ الأمر {{counterأمر}} في {{time}}';
                              updatePreview();
                              setDialogState(() {});
                            },
                          ),
                          _buildTemplateChip(
                            label: '📊 إحصائيات',
                            onPressed: () {
                              textController.text = 'الإحصائيات اليومية\nالتاريخ: {{date}}\nرقم التقرير: {{counterتقرير}}\nالملاحظات: {{clipboard}}';
                              updatePreview();
                              setDialogState(() {});
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.preview, size: 16, color: Colors.blue),
                                const SizedBox(width: 6),
                                const Text('المعاينة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '👁️ تحديث تلقائي',
                                    style: TextStyle(fontSize: 9, color: Colors.blue.shade700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                previewText.isEmpty ? '📝 سيظهر النص هنا...' : previewText,
                                style: TextStyle(
                                  color: previewText.isEmpty ? Colors.grey.shade400 : Colors.black87,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: repeatController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '🔄 التكرار',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: delayController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '⏱️ تأخير (مللي ثانية)',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text(
                            '💡 انقر الأزرار لإدراج المتغيرات في النص',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                          ],
                        ),
                      ),
                    ),
                  ),
                actions: [
                  FilledButton.icon(
                    onPressed: () {
                      final text = textController.text.trim();
                      if (text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('يرجى إدخال النص')),
                        );
                        return;
                      }
                      if (selectedWindow.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('اختر النافذة المستهدفة لهذه الخطوة أولاً')),
                        );
                        return;
                      }
                      final repeat = int.tryParse(repeatController.text) ?? 1;
                      final delay = int.tryParse(delayController.text) ?? 0;
                      Navigator.pop(context, {
                        'text': text,
                        'repeat': repeat < 1 ? 1 : repeat,
                        'delay': delay < 0 ? 0 : delay,
                        'targetWindow': selectedWindow,
                        'windowAlias': _windowIdentityForSelection(
                          selectedWindow,
                          windowMatch,
                          windowAliasController.text,
                        ),
                        'windowMatch': windowMatch,
                      });
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('حفظ'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('إلغاء'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (result == null) return;

    final text = result['text'] as String;
    final repeat = result['repeat'] as int;
    final delay = result['delay'] as int;
    final targetWindow = result['targetWindow'] as String? ?? '';
    final windowAlias = result['windowAlias'] as String? ?? '';

    _captureEditorChange();
    setState(() {
      if (existing != null && index != null) {
        existing.text = text;
        existing.repeat = repeat;
        existing.delayMs = delay;
        existing.targetWindow = targetWindow;
        existing.windowAlias = windowAlias;
        existing.windowMatch = result['windowMatch'] as String? ?? 'title';
      } else {
        _steps.add(AutomationStep(
          id: _newId(),
          type: StepType.text,
          text: text,
          repeat: repeat,
          delayMs: delay,
          targetWindow: targetWindow,
          windowAlias: windowAlias,
          windowMatch: result['windowMatch'] as String? ?? 'title',
        ));
      }
    });
  }

  // ==================== دوال المفتاح والماوس والانتظار ====================
  Future<void> _showKeyDialog({AutomationStep? existing, int? index}) async {
    if (!mounted) return;
    const modifiers = ['NONE', 'CTRL', 'ALT', 'SHIFT', 'WIN'];
    String selectedKey = existing?.key ?? 'ENTER';
    String selectedModifier = 'NONE';
    if (existing != null && existing.modifiers.isNotEmpty) {
      selectedModifier = existing.modifiers.first;
    }
    if (!allKeys.any((k) => k.code == selectedKey)) selectedKey = 'ENTER';
    if (!modifiers.contains(selectedModifier)) selectedModifier = 'NONE';
    final repeatController = TextEditingController(text: '${existing?.repeat ?? 1}');
    final delayController = TextEditingController(text: '${existing?.delayMs ?? 0}');
    final windowAliasController = TextEditingController(text: existing?.windowAlias ?? '');
    String selectedWindow = existing?.targetWindow.isNotEmpty == true
        ? existing!.targetWindow
        : _inheritedTargetWindowForNewStep();
    String windowMatch = existing?.windowMatch ?? 'title';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) {
                  repeatController.dispose();
                  delayController.dispose();
                  windowAliasController.dispose();
                }
              },
              child: AlertDialog(
                title: Text(existing == null ? 'إضافة مفتاح (مع اختصار)' : 'تعديل المفتاح'),
                content: SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStepWindowSelector(
                        selectedWindow: selectedWindow,
                        initialMatch: windowMatch,
                        onChanged: (value) {
                          setDialogState(() => selectedWindow = value ?? '');
                        },
                        onMatchChanged: (value) {
                          setDialogState(() => windowMatch = value ?? 'title');
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedModifier,
                        decoration: const InputDecoration(labelText: 'المعدّل', border: OutlineInputBorder()),
                        items: modifiers.map((mod) => DropdownMenuItem(
                          value: mod,
                          child: Text(mod == 'NONE' ? 'بدون' : mod),
                        )).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() { selectedModifier = value; });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedKey,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'المفتاح الأساسي', border: OutlineInputBorder()),
                        items: allKeys.map((key) => DropdownMenuItem(
                          value: key.code,
                          child: Text(key.name),
                        )).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() { selectedKey = value; });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: repeatController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'التكرار', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: delayController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'بعدها انتظر (مللي ثانية)', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  FilledButton(
                    onPressed: () {
                      if (selectedWindow.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('اختر النافذة المستهدفة لهذه الخطوة أولاً')),
                        );
                        return;
                      }
                      final repeat = int.tryParse(repeatController.text) ?? 1;
                      final delay = int.tryParse(delayController.text) ?? 0;
                      Navigator.pop(context, {
                        'key': selectedKey,
                        'modifier': selectedModifier,
                        'repeat': repeat < 1 ? 1 : repeat,
                        'delay': delay < 0 ? 0 : delay,
                        'targetWindow': selectedWindow,
                        'windowAlias': _windowIdentityForSelection(
                          selectedWindow,
                          windowMatch,
                          windowAliasController.text,
                        ),
                        'windowMatch': windowMatch,
                      });
                    },
                    child: const Text('حفظ'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('إلغاء'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (result == null) return;
    final key = result['key'] as String;
    final modifier = result['modifier'] as String;
    final repeat = result['repeat'] as int;
    final delay = result['delay'] as int;
    final targetWindow = result['targetWindow'] as String? ?? '';
    final windowAlias = result['windowAlias'] as String? ?? '';

    _captureEditorChange();
    setState(() {
      if (existing != null && index != null) {
        existing.key = key;
        existing.modifiers = modifier == 'NONE' ? [] : [modifier];
        existing.repeat = repeat;
        existing.delayMs = delay;
        existing.targetWindow = targetWindow;
        existing.windowAlias = windowAlias;
        existing.windowMatch = windowMatch;
      } else {
        _steps.add(AutomationStep(
          id: _newId(),
          type: StepType.key,
          key: key,
          modifiers: modifier == 'NONE' ? [] : [modifier],
          repeat: repeat,
          delayMs: delay,
          targetWindow: targetWindow,
          windowAlias: windowAlias,
          windowMatch: windowMatch,
        ));
      }
    });
  }

  Future<void> _showMouseDialog({AutomationStep? existing, int? index}) async {
    if (!mounted) return;
    final xController = TextEditingController(text: '${existing?.x ?? 0}');
    final yController = TextEditingController(text: '${existing?.y ?? 0}');
    String selectedButton = existing?.button ?? 'left';
    bool doubleClick = existing?.doubleClick ?? false;
    final repeatController = TextEditingController(text: '${existing?.repeat ?? 1}');
    final delayController = TextEditingController(text: '${existing?.delayMs ?? 0}');
    final windowAliasController = TextEditingController(text: existing?.windowAlias ?? '');
    String selectedWindow = existing?.targetWindow.isNotEmpty == true
        ? existing!.targetWindow
        : _inheritedTargetWindowForNewStep();
    String windowMatch = existing?.windowMatch ?? 'title';
    final focusNode = FocusNode();

    Future<void> fetchCurrentCoordinates() async {
      try {
        final position = await _nativeAutomation.getMousePosition();
        if (position == null) {
          throw const FormatException('لم يُرجع Windows إحداثيات صالحة.');
        }
        xController.text = position['x'].toString();
        yController.text = position['y'].toString();
      } on PlatformException catch (error) {
        _handleError(
          'تعذر التقاط موضع الماوس عبر Windows. تأكد من تشغيل نسخة Windows المحدثة ثم حاول مرة أخرى.',
          exception: error,
        );
      } catch (error) {
        _handleError('فشل جلب إحداثيات الماوس', exception: Exception(error));
      }
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          focusNode.requestFocus();
        });
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) {
                  xController.dispose();
                  yController.dispose();
                  repeatController.dispose();
                  delayController.dispose();
                  windowAliasController.dispose();
                  focusNode.dispose();
                }
              },
              child: KeyboardListener(
                focusNode: focusNode,
                onKeyEvent: (KeyEvent event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.f2) {
                    // KeyRepeatEvent is intentionally excluded so holding F2
                    // cannot issue repeated native calls.
                    fetchCurrentCoordinates();
                  }
                },
                child: AlertDialog(
                  title: Text(existing == null ? 'إضافة نقرة ماوس' : 'تعديل نقرة الماوس'),
                  content: SizedBox(
                    width: 450,
                    height: MediaQuery.sizeOf(context).height * 0.55,
                    child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        _buildStepWindowSelector(
                          selectedWindow: selectedWindow,
                          initialMatch: windowMatch,
                          onChanged: (value) {
                            setDialogState(() => selectedWindow = value ?? '');
                          },
                          onMatchChanged: (value) {
                            setDialogState(() => windowMatch = value ?? 'title');
                          },
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '💡  حرك الماوس إلى المكان المطلوب واضغط F2 للالتقاط السريع',
                            style: TextStyle(fontSize: 12, color: Colors.black87),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: xController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'الإحداثي X', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.my_location, color: Colors.indigo),
                              tooltip: 'الحصول على إحداثيات الماوس الحالية',
                              onPressed: () async {
                                await fetchCurrentCoordinates();
                                setDialogState(() {});
                              },
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: yController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'الإحداثي Y', border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedButton,
                          decoration: const InputDecoration(labelText: 'الزر', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'left', child: Text('زر أيسر')),
                            DropdownMenuItem(value: 'right', child: Text('زر أيمن')),
                            DropdownMenuItem(value: 'middle', child: Text('زر أوسط')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() { selectedButton = value; });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          title: const Text('نقرة مزدوجة (Double Click)'),
                          value: doubleClick,
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() { doubleClick = val; });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: repeatController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'التكرار', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: delayController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'بعدها انتظر (مللي ثانية)', border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                          ],
                        ),
                      ),
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () {
                        final x = int.tryParse(xController.text) ?? 0;
                        final y = int.tryParse(yController.text) ?? 0;
                        if (selectedWindow.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('اختر النافذة المستهدفة لهذه الخطوة أولاً')),
                          );
                          return;
                        }
                        final repeat = int.tryParse(repeatController.text) ?? 1;
                        final delay = int.tryParse(delayController.text) ?? 0;
                        Navigator.pop(context, {
                          'x': x,
                          'y': y,
                          'button': selectedButton,
                          'doubleClick': doubleClick,
                          'repeat': repeat < 1 ? 1 : repeat,
                          'delay': delay < 0 ? 0 : delay,
                          'targetWindow': selectedWindow,
                          'windowAlias': _windowIdentityForSelection(
                            selectedWindow,
                            windowMatch,
                            windowAliasController.text,
                          ),
                          'windowMatch': windowMatch,
                        });
                      },
                      child: const Text('حفظ'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('إلغاء'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (result == null) return;
    final x = result['x'] as int;
    final y = result['y'] as int;
    final button = result['button'] as String;
    final doubleClickVal = result['doubleClick'] as bool;
    final repeat = result['repeat'] as int;
    final delay = result['delay'] as int;
    final targetWindow = result['targetWindow'] as String? ?? '';
    final windowAlias = result['windowAlias'] as String? ?? '';

    _captureEditorChange();
    setState(() {
      if (existing != null && index != null) {
        existing.x = x;
        existing.y = y;
        existing.button = button;
        existing.doubleClick = doubleClickVal;
        existing.repeat = repeat;
        existing.delayMs = delay;
        existing.targetWindow = targetWindow;
        existing.windowAlias = windowAlias;
      } else {
        _steps.add(AutomationStep(
          id: _newId(),
          type: StepType.mouse,
          x: x,
          y: y,
          button: button,
          doubleClick: doubleClickVal,
          repeat: repeat,
          delayMs: delay,
          targetWindow: targetWindow,
          windowAlias: windowAlias,
          windowMatch: windowMatch,
        ));
      }
    });
  }

  Future<void> _showDelayDialog({AutomationStep? existing, int? index}) async {
    if (!mounted) return;
    final controller = TextEditingController(text: '${existing?.delayMs ?? 1000}');

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) controller.dispose();
          },
          child: AlertDialog(
            title: Text(existing == null ? 'إضافة انتظار' : 'تعديل الانتظار'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المدة بالمللي ثانية', hintText: '1200', border: OutlineInputBorder()),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  final delay = int.tryParse(controller.text) ?? 0;
                  Navigator.pop(context, delay < 0 ? 0 : delay);
                },
                child: const Text('حفظ'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (result == null) return;
    _captureEditorChange();
    if (existing != null && index != null) {
      setState(() {
        existing.delayMs = result;
      });
    } else {
      setState(() {
        _steps.add(AutomationStep(
          id: _newId(),
          type: StepType.delay,
          delayMs: result,
        ));
      });
    }
  }

  Future<void> _showSetCounterDialog({AutomationStep? existing, int? index}) async {
    if (!mounted) return;
    final nameController = TextEditingController(text: existing?.counterName ?? '');
    final valueController = TextEditingController(text: existing?.counterValue.toString() ?? '1');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              nameController.dispose();
              valueController.dispose();
            }
          },
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(existing == null ? 'تعيين عداد' : 'تعديل تعيين العداد'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'اسم العداد (مثل: فرع, يوم)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: valueController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'القيمة', border: OutlineInputBorder()),
                    ),
                  ],
                ),
                actions: [
                  FilledButton(
                    onPressed: () {
                      final name = nameController.text.trim();
                      final value = int.tryParse(valueController.text) ?? 1;
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('يرجى إدخال اسم العداد')),
                        );
                        return;
                      }
                      Navigator.pop(context, {
                        'name': name,
                        'value': value,
                      });
                    },
                    child: const Text('حفظ'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('إلغاء'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (!mounted) return;
    if (result == null) return;
    final name = result['name'] as String;
    final value = result['value'] as int;

    _captureEditorChange();
    setState(() {
      if (existing != null && index != null) {
        existing.counterName = name;
        existing.counterValue = value;
      } else {
        _steps.add(AutomationStep(
          id: _newId(),
          type: StepType.setCounter,
          counterName: name,
          counterValue: value,
        ));
      }
    });
  }

  Future<void> _showIncrementCounterDialog({AutomationStep? existing, int? index}) async {
    if (!mounted) return;
    final nameController = TextEditingController(text: existing?.counterName ?? '');
    final amountController = TextEditingController(
        text: existing?.incrementAmount.toString() ?? '1');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              nameController.dispose();
              amountController.dispose();
            }
          },
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(existing == null ? 'زيادة عداد' : 'تعديل زيادة العداد'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'اسم العداد (مثل: فرع, يوم)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'مقدار الزيادة (افتراضي 1)', border: OutlineInputBorder()),
                    ),
                  ],
                ),
                actions: [
                  FilledButton(
                    onPressed: () {
                      final name = nameController.text.trim();
                      final amount = int.tryParse(amountController.text) ?? 1;
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('يرجى إدخال اسم العداد')),
                        );
                        return;
                      }
                      Navigator.pop(context, {
                        'name': name,
                        'amount': amount,
                      });
                    },
                    child: const Text('حفظ'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('إلغاء'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (!mounted) return;
    if (result == null) return;
    final name = result['name'] as String;
    final amount = result['amount'] as int;

    _captureEditorChange();
    setState(() {
      if (existing != null && index != null) {
        existing.counterName = name;
        existing.incrementAmount = amount;
      } else {
        _steps.add(AutomationStep(
          id: _newId(),
          type: StepType.incrementCounter,
          counterName: name,
          incrementAmount: amount,
        ));
      }
    });
  }

  void _showShortcutDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredEntries = _shortcuts.entries.where((entry) {
              final search = searchQuery.toLowerCase();
              return entry.key.toLowerCase().contains(search) ||
                  entry.value.description.toLowerCase().contains(search) ||
                  entry.value.category.toLowerCase().contains(search);
            }).toList();

            Map<String, List<MapEntry<String, Shortcut>>> grouped = {};
            for (var entry in filteredEntries) {
              final category = entry.value.category;
              grouped.putIfAbsent(category, () => []).add(entry);
            }
            final sortedCategories = grouped.keys.toList()..sort();

            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, result) {},
              child: AlertDialog(
                title: const Text('اختر اختصاراً جاهزاً'),
                content: SizedBox(
                  width: 420,
                  height: 480,
                  child: Column(
                    children: [
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'بحث...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            searchQuery = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filteredEntries.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text('لا توجد اختصارات تطابق البحث',
                                        style: TextStyle(color: Colors.grey.shade600)),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: sortedCategories.length,
                                itemBuilder: (context, categoryIndex) {
                                  final category = sortedCategories[categoryIndex];
                                  final items = grouped[category]!;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        child: Text(
                                          category,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.indigo.shade700,
                                          ),
                                        ),
                                      ),
                                      ...items.map((entry) {
                                        final shortcut = entry.value;
                                        String keyDisplay = shortcut.key;
                                        if (shortcut.modifiers.isNotEmpty) {
                                          keyDisplay =
                                              '${shortcut.modifiers.join('+')}+$keyDisplay';
                                        }
                                        return ListTile(
                                          dense: true,
                                          leading: Icon(Icons.keyboard, color: Colors.amber.shade700),
                                          title: Text(entry.key),
                                          subtitle: Text(
                                            '${shortcut.description}  •  $keyDisplay',
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                          ),
                                          onTap: () {
                                            _captureEditorChange();
                                            setState(() {
                                              final targetWindow = _inheritedTargetWindowForNewStep();
                                            _steps.add(AutomationStep(
                                              id: _newId(),
                                              type: StepType.key,
                                              key: shortcut.key,
                                              modifiers: shortcut.modifiers,
                                              repeat: 1,
                                              delayMs: 0,
                                              targetWindow: targetWindow,
                                              windowAlias: _windowIdForTitle(targetWindow),
                                              windowMatch: 'title',
                                            ));
                                            });
                                            Navigator.pop(context);
                                          },
                                        );
                                      }),
                                      if (categoryIndex < sortedCategories.length - 1)
                                        const Divider(height: 4, thickness: 1),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==================== دوال التكرار والنطاق ====================
  void _showSelectRepeatStepsDialog() {
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد خطوات لتحديدها')),
      );
      return;
    }

    List<int> tempSelected = List.from(_selectedRepeatSteps);
    int repeatCount = _loopRangeCount;
    int delayMs = _loopDelayMs;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('تحديد خطوات للتكرار'),
              content: SizedBox(
                width: 450,
                height: 400,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: _steps.length,
                        itemBuilder: (context, index) {
                          final step = _steps[index];
                          final isSelected = tempSelected.contains(index);
                          return CheckboxListTile(
                            title: Text('${index+1}. ${_stepTitle(step)}'),
                            subtitle: Text(_stepDescription(step),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            value: isSelected,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  if (!tempSelected.contains(index)) {
                                    tempSelected.add(index);
                                  }
                                } else {
                                  tempSelected.remove(index);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'عدد التكرارات',
                                border: OutlineInputBorder()),
                            onChanged: (val) {
                              final c = int.tryParse(val);
                              if (c != null && c > 0) repeatCount = c;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'التأخير (مللي ثانية)',
                                border: OutlineInputBorder()),
                            onChanged: (val) {
                              final d = int.tryParse(val);
                              if (d != null && d >= 0) delayMs = d;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
                actions: [
                  FilledButton(
                    onPressed: () {
                      setState(() {
                      _selectedRepeatSteps = List.from(tempSelected);
                      _loopRangeCount = repeatCount;
                      _loopDelayMs = delayMs;
                      _loopRangeStart = null;
                      _loopRangeEnd = null;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('حفظ'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _clearSelectedSteps() {
    setState(() {
      _selectedRepeatSteps.clear();
      _loopRangeStart = null;
      _loopRangeEnd = null;
    });
  }

  void _showSetRangeDialog() {
    if (_selectedRepeatSteps.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لديك خطوات محددة بالفعل. قم بإلغاء التحديد أولاً.')),
      );
      return;
    }
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد خطوات لتحديد نطاق')),
      );
      return;
    }

    int start = _loopRangeStart ?? 0;
    int end = _loopRangeEnd ?? _steps.length - 1;
    int count = _loopRangeCount;
    int delay = _loopDelayMs;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, result) {},
              child: AlertDialog(
                title: const Text('تعيين نطاق التكرار'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: start,
                      decoration: const InputDecoration(labelText: 'خطوة البداية'),
                      items: List.generate(_steps.length, (i) {
                        return DropdownMenuItem(value: i, child: Text('${i+1} - ${_stepTitle(_steps[i])}'));
                      }),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() { start = val; });
                          if (end < start) {
                            setDialogState(() { end = start; });
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: end,
                      decoration: const InputDecoration(labelText: 'خطوة النهاية'),
                      items: List.generate(_steps.length, (i) {
                        return DropdownMenuItem(value: i, child: Text('${i+1} - ${_stepTitle(_steps[i])}'));
                      }),
                      onChanged: (val) {
                        if (val != null && val >= start) {
                          setDialogState(() { end = val; });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'عدد التكرارات', border: OutlineInputBorder()),
                      onChanged: (val) {
                        final c = int.tryParse(val);
                        if (c != null && c > 0) count = c;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'التأخير بين التكرارات (مللي ثانية)', border: OutlineInputBorder()),
                      onChanged: (val) {
                        final d = int.tryParse(val);
                        if (d != null && d >= 0) delay = d;
                      },
                    ),
                  ],
                ),
                actions: [
                  FilledButton(
                    onPressed: () {
                      if (count > 0 && start <= end) {
                        setState(() {
                          _loopRangeStart = start;
                          _loopRangeEnd = end;
                          _loopRangeCount = count;
                          _loopDelayMs = delay;
                          _selectedRepeatSteps.clear();
                        });
                        Navigator.pop(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تأكد من صحة البيانات')),
                        );
                      }
                    },
                    child: const Text('تطبيق'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _clearLoopRange() {
    setState(() {
      _loopRangeStart = null;
      _loopRangeEnd = null;
      _selectedRepeatSteps.clear();
    });
  }

  void _showLoopRangeCountDialog() {
    final controller = TextEditingController(text: _loopRangeCount.toString());
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) controller.dispose();
          },
          child: AlertDialog(
            title: const Text('عدد مرات تكرار النطاق'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'عدد التكرارات', border: OutlineInputBorder()),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  final val = int.tryParse(controller.text);
                  if (val != null && val > 0) {
                    if (mounted) {
                      setState(() { _loopRangeCount = val; });
                    }
                  }
                  Navigator.pop(context);
                },
                child: const Text('حفظ'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== دوال تكرار السيناريو ====================
  Future<void> _showScenarioRepeatDialog() async {
    if (_running) return;
    final countController = TextEditingController(text: '$_scenarioRepeatCount');
    final intervalController = TextEditingController(text: '$_scenarioIntervalMs');
    bool periodic = _scenarioPeriodic;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('تكرار السيناريو'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تشغيل دوري مستمر'),
                      subtitle: const Text('يستمر حتى تضغط زر إيقاف'),
                      value: periodic,
                      onChanged: (value) => setDialogState(() => periodic = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: countController,
                      enabled: !periodic,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'عدد مرات تشغيل السيناريو',
                        helperText: 'يُستخدم في الوضع المحدد فقط',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الفاصل بين دورات السيناريو (مللي ثانية)',
                        helperText: 'مثال: 5000 تعني 5 ثوانٍ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    final count = int.tryParse(countController.text.trim());
                    final interval = int.tryParse(intervalController.text.trim());
                    if (!periodic && (count == null || count < 1)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('أدخل عدداً صحيحاً أكبر من صفر')),
                      );
                      return;
                    }
                    if (interval == null || interval < 0 || (periodic && interval < 100)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(periodic
                              ? 'في الوضع الدوري يجب أن يكون الفاصل 100ms على الأقل'
                              : 'أدخل فاصلاً زمنياً صحيحاً'),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _scenarioPeriodic = periodic;
                      _scenarioRepeatCount = count ?? 1;
                      _scenarioIntervalMs = interval;
                    });
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('حفظ'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        );
      },
    );
    countController.dispose();
    intervalController.dispose();
  }

  Future<Map<String, String>?> _collectScenarioVariables() async {
    final variables = <String>{};
    final pattern = RegExp(r'\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}');
    void scan(Object? value) {
      if (value is String) {
        for (final match in pattern.allMatches(value)) {
          variables.add(match.group(1)!);
        }
      } else if (value is Map) {
        for (final value in value.values) {
          scan(value);
        }
      } else if (value is Iterable) {
        for (final item in value) {
          scan(item);
        }
      }
    }
    for (final step in _steps) {
      scan(step.text);
      scan(step.command);
      scan(step.commandArguments);
    }
    if (variables.isEmpty || !mounted) return <String, String>{};

    final controllers = <String, TextEditingController>{
      for (final name in variables) name: TextEditingController(),
    };
    try {
      final result = await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('بيانات السيناريو'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('أدخل القيم المطلوبة قبل بدء التشغيل:'),
                ),
                const SizedBox(height: 12),
                for (final name in variables)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: controllers[name],
                      autofocus: name == variables.first,
                      textDirection: TextDirection.rtl,
                      decoration: InputDecoration(
                        labelText: name,
                        hintText: 'مثال: اليمن',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop({
                  for (final entry in controllers.entries)
                    entry.key: entry.value.text,
                });
              },
              child: const Text('تشغيل'),
            ),
          ],
        ),
      );
      return result;
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  String _resolveScenarioText(String value, Map<String, String> variables) {
    return value.replaceAllMapped(
      RegExp(r'\\{\\{\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*\\}\\}'),
      (match) => variables[match.group(1)] ?? match.group(0)!,
    );
  }

  Map<String, dynamic> _resolveScenarioArguments(
    Map<String, dynamic> arguments,
    Map<String, String> variables,
  ) {
    dynamic resolve(dynamic value) {
      if (value is String) return _resolveScenarioText(value, variables);
      if (value is Map) {
        return <String, dynamic>{
          for (final entry in value.entries)
            entry.key.toString(): resolve(entry.value),
        };
      }
      if (value is Iterable) return value.map(resolve).toList();
      return value;
    }
    return Map<String, dynamic>.from(resolve(arguments) as Map);
  }

  // ==================== دالة التشغيل الرئيسية ====================
  Future<void> _runAutomation() async {
    if (_steps.isEmpty || _running) {
      if (_steps.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ لا توجد خطوات لتنفيذها. أضف خطوات أولاً.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final variables = await _collectScenarioVariables();
    if (variables == null) return;

    final fallbackTargetWindow = _selectedWindowForDropdown?.trim();
    final needsFallbackWindow = _steps.any((step) {
      final needsWindow = step.type == StepType.text ||
          step.type == StepType.key ||
          step.type == StepType.mouse ||
          step.type == StepType.waitForWindow ||
          step.type == StepType.semanticCommand;
      return needsWindow &&
          step.targetWindow.trim().isEmpty &&
          step.windowAlias.trim().isEmpty;
    });

    if (needsFallbackWindow &&
        (fallbackTargetWindow == null || fallbackTargetWindow.isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ اختر نافذة للخطوات التي لا تحتوي على نافذة محفوظة.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    List<int> stepsToRepeat = [];
    if (_selectedRepeatSteps.isNotEmpty) {
      stepsToRepeat = List.from(_selectedRepeatSteps);
    } else if (_loopRangeStart != null && _loopRangeEnd != null) {
      stepsToRepeat =
          List.generate(_loopRangeEnd! - _loopRangeStart! + 1, (i) => _loopRangeStart! + i);
    } else {
      stepsToRepeat = List.generate(_steps.length, (i) => i);
    }
    stepsToRepeat.sort();

    int loopCount = _loopRangeCount;
    int loopDelayMs = _loopDelayMs;
    final random = Random();

    _counterValues = Map.from(_counterStarts);

    setState(() {
      _running = true;
      _stopRequested = false;
      _currentStep = null;
      _currentLoopIteration = 0;
      _totalLoopIterations = loopCount;
      _currentScenarioIteration = 0;
      _totalScenarioIterations = _scenarioPeriodic ? 0 : _scenarioRepeatCount;
    });

    bool runFailed = false;
    AppLogger.info(
      'Starting scenario execution: ${stepsToRepeat.length} steps, loops=$loopCount, scenarios=${_scenarioPeriodic ? 'periodic' : _scenarioRepeatCount}.',
      name: 'automation',
    );
    try {
      for (int scenarioIter = 0;
          _scenarioPeriodic || scenarioIter < _scenarioRepeatCount;
          scenarioIter++) {
        if (!_running) break;
        setState(() {
          _currentScenarioIteration = scenarioIter + 1;
        });

        for (int loopIter = 0; loopIter < loopCount; loopIter++) {
          if (!_running) break;
          setState(() {
            _currentLoopIteration = loopIter + 1;
          });

          for (int i in stepsToRepeat) {
            if (!_running) break;
            final originalStep = _steps[i];
            final variablesForStep = variables;
            final step = originalStep.copy();
            step.text = _resolveScenarioText(step.text, variablesForStep);
            step.command = _resolveScenarioText(step.command, variablesForStep);
            step.commandArguments = _resolveScenarioArguments(step.commandArguments, variablesForStep);
            if (step.type == StepType.loop) continue;

            setState(() {
              _currentStep = i;
            });

            if (_randomDelayEnabled && _randomDelayMax > 0) {
              final minimum = _randomDelayMin.clamp(0, _randomDelayMax).toInt();
              final maximum = max(minimum, _randomDelayMax).toInt();
              final delay = minimum + random.nextInt(maximum - minimum + 1);
              await _wait(delay);
            }

            final needsWindow = step.type == StepType.text ||
                step.type == StepType.key ||
                step.type == StepType.mouse ||
                step.type == StepType.waitForWindow ||
                step.type == StepType.semanticCommand;
            final savedTarget = step.targetWindow.trim();
            final windowId = step.windowAlias.trim();
            final targetWindow = savedTarget.isNotEmpty
                ? savedTarget
                : (fallbackTargetWindow ?? '');
            final isWindowChangingKey = step.type == StepType.key &&
                step.windowChanged &&
                step.previousWindow?.trim().isNotEmpty == true &&
                targetWindow.isNotEmpty &&
                step.previousWindow!.trim() != targetWindow;

            if (needsWindow) {
              if (targetWindow.isEmpty && windowId.isEmpty) {
                continue;
              }

              if (isWindowChangingKey) {
                // A transition key must be sent to the window that was active
                // before the key, not to the window that became active after
                // it. This is essential for Enter in the Run dialog and for
                // ALT+TAB: pre-activating the destination would make the key
                // switch away from the intended destination.
                final sourceWindow = step.previousWindow!.trim();
                final sourceReady = await _waitForWindow(
                  sourceWindow,
                  windowAlias: step.previousWindow?.trim() ?? '',
                  timeoutMs: 2500,
                );
                if (!sourceReady) {
                  _running = false;
                  if (mounted) {
                    _handleError(
                      'توقف التشغيل: تعذر تفعيل نافذة ما قبل الانتقال للخطوة ${i + 1}: "$sourceWindow"',
                    );
                  }
                  break;
                }
              } else {
                final targetReady = await _waitForWindow(
                  targetWindow,
                  windowAlias: windowId,
                  timeoutMs: step.type == StepType.waitForWindow
                      ? step.waitTimeoutMs
                      : 5000,
                );
                if (!targetReady) {
                  _running = false;
                  if (mounted) {
                    _handleError(
                      step.type == StepType.waitForWindow
                          ? 'توقف التشغيل: لم تظهر نافذة الانتظار للخطوة ${i + 1}: "$targetWindow"'
                          : 'توقف التشغيل: تعذر تفعيل نافذة الخطوة ${i + 1}: "$targetWindow"',
                    );
                  }
                  break;
                }
              }
            }

            if (step.type == StepType.semanticCommand) {
              final command = step.command.trim();
              if (command.isEmpty) {
                _running = false;
                if (mounted) _handleError('توقف التشغيل: الأمر الدلالي في الخطوة ${i + 1} فارغ.');
                break;
              }
              try {
          await _nativeAutomation.executeSemanticCommand(
            windowTitle: step.targetWindow,
            windowAlias: step.windowAlias,
            command: step.command,
            arguments: step.commandArguments,
            waitTimeoutMs: step.waitTimeoutMs,
          );
              } on PlatformException catch (error) {
                _running = false;
                if (mounted) {
                  _handleError(
                    'توقف التشغيل: فشل الأمر الدلالي في الخطوة ${i + 1}: ${error.message ?? error.code}',
                    exception: error,
                  );
                }
                break;
              }
              await _wait(step.delayMs);
              if (!_running) break;
              continue;
            }

            if (step.type == StepType.setCounter) {
              final key = 'counter_${step.counterName}';
              _counterValues[key] = step.counterValue;
              _counterStarts[key] = step.counterValue;
              continue;
            }

            if (step.type == StepType.incrementCounter) {
              final key = 'counter_${step.counterName}';
              if (_counterValues.containsKey(key)) {
                _counterValues[key] = (_counterValues[key] ?? 0) + step.incrementAmount;
              } else {
                _counterValues[key] = 1 + step.incrementAmount;
                _counterStarts[key] = 1;
              }
              continue;
            }

            if (step.type == StepType.delay) {
              await _wait(step.delayMs);
              if (!_running) break;
              continue;
            }

            if (step.type == StepType.text) {
              final processedText = await _processText(step.text);
              for (var r = 0; r < step.repeat; r++) {
                if (!_running) break;
                await _invokeWithRetry(
                  'text',
                  {'text': processedText},
                  action: 'Text input',
                );
              }
              await _wait(step.delayMs);
              if (!_running) break;
              continue;
            }

            if (step.type == StepType.key) {
              for (var r = 0; r < step.repeat; r++) {
                if (!_running) break;
                final Map<String, dynamic> args = {'key': step.key};
                if (step.modifiers.isNotEmpty) args['modifiers'] = step.modifiers;
                await _invokeWithRetry('key', args, action: 'Key input');
                if (step.repeat > 1 && r < step.repeat - 1) {
                  await _wait(15);
                }
              }
              if (_running && isWindowChangingKey) {
                // Verify the result without activating the destination again.
                // If the key failed, do not send subsequent clicks or text to
                // the still-active Run/application window.
                final destinationReady = await _waitForActiveWindow(
                  targetWindow,
                  timeoutMs: 3500,
                );
                if (!destinationReady) {
                  _running = false;
                  if (mounted) {
                    _handleError(
                      'توقف التشغيل: لم تنتقل النافذة بعد المفتاح ${i + 1} إلى "$targetWindow". لم تُرسل الخطوة التالية.',
                    );
                  }
                  break;
                }
              }
              await _wait(step.delayMs);
              if (!_running) break;
              continue;
            }

            if (step.type == StepType.mouse) {
              for (var r = 0; r < step.repeat; r++) {
                if (!_running) break;
                await _invokeWithRetry(
                  'mouse_click',
                  {
                    'x': step.x,
                    'y': step.y,
                    'button': step.button,
                    'double_click': step.doubleClick,
                  },
                  action: 'Mouse input',
                );
              }
              await _wait(step.delayMs);
              if (!_running) break;
              continue;
            }
          }

          if (loopIter < loopCount - 1 && loopDelayMs > 0) {
            await _wait(loopDelayMs);
            if (!_running) break;
          }
        }

        if (_running && (_scenarioPeriodic || scenarioIter < _scenarioRepeatCount - 1)) {
          await _wait(_scenarioIntervalMs);
        }
      }
    } on PlatformException catch (e) {
      runFailed = true;
      _running = false;
      _handleError(e.message ?? 'حدث خطأ في النظام', exception: Exception(e));
    } catch (e) {
      runFailed = true;
      _running = false;
      _handleError('حدث خطأ أثناء التشغيل', exception: Exception(e));
    } finally {
      _delayTimer?.cancel();
      if (mounted) {
        setState(() {
          _running = false;
          _currentStep = null;
          _currentLoopIteration = 0;
          _currentScenarioIteration = 0;
        });
        if (!runFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_stopRequested
                  ? '⏹️ تم إيقاف السيناريو'
                  : '✅ تم الانتهاء من تشغيل السيناريو'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _stopAutomation() {
    _stopRequested = true;
    setState(() { _running = false; });
    _delayTimer?.cancel();
    if (_pendingDelay != null && !_pendingDelay!.isCompleted) {
      _pendingDelay!.complete();
    }
  }

  // ==================== دوال إدارة الخطوات ====================
  void _captureEditorChange() {
    _editorController.capture(_steps);
  }

  void _restoreEditorSnapshot(List<AutomationStep> snapshot) {
    setState(() {
      _steps
        ..clear()
        ..addAll(snapshot.map((step) => step.copy()));
      _selectedRepeatSteps.clear();
      _loopRangeStart = null;
      _loopRangeEnd = null;
    });
  }

  void _undoEditorChange() {
    if (_running) return;
    final snapshot = _editorController.undo(_steps);
    if (snapshot == null) return;
    _restoreEditorSnapshot(snapshot);
  }

  void _redoEditorChange() {
    if (_running) return;
    final snapshot = _editorController.redo(_steps);
    if (snapshot == null) return;
    _restoreEditorSnapshot(snapshot);
  }

  void _deleteStep(int index) {
    if (_running || index < 0 || index >= _steps.length) return;
    _captureEditorChange();
    setState(() {
      _steps.removeAt(index);
      _selectedRepeatSteps.remove(index);
      if (_loopRangeStart == index) _loopRangeStart = null;
      if (_loopRangeEnd == index) _loopRangeEnd = null;
    });
  }

  void _duplicateStep(int index) {
    if (_running || index < 0 || index >= _steps.length) return;
    _captureEditorChange();
    final source = _steps[index];
    final copy = source.copy(id: _newId());
    setState(() { _steps.insert(index + 1, copy); });
  }

  void _moveStep(int oldIndex, int newIndex) {
    if (_running || oldIndex < 0 || oldIndex >= _steps.length) return;
    if (newIndex < 0 || newIndex > _steps.length || newIndex == oldIndex) {
      return;
    }
    _captureEditorChange();
    setState(() {
      final item = _steps.removeAt(oldIndex);
      final destination = newIndex.clamp(0, _steps.length).toInt();
      _steps.insert(destination, item);
    });
  }

  void _editStep(int index) {
    if (_running) return;
    final step = _steps[index];
    switch (step.type) {
      case StepType.text:
        _showEnhancedTextDialog(existing: step, index: index);
        break;
      case StepType.key:
        _showKeyDialog(existing: step, index: index);
        break;
      case StepType.mouse:
        _showMouseDialog(existing: step, index: index);
        break;
      case StepType.delay:
        _showDelayDialog(existing: step, index: index);
        break;
      case StepType.loop:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خطوات الحلقة غير مدعومة، استخدم تكرار النطاق')),
        );
        break;
      case StepType.setCounter:
        _showSetCounterDialog(existing: step, index: index);
        break;
      case StepType.incrementCounter:
        _showIncrementCounterDialog(existing: step, index: index);
        break;
      case StepType.waitForWindow:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعديل خطوة انتظار النافذة غير مدعوم حالياً')),
        );
        break;
      case StepType.semanticCommand:
        _showSemanticCommandDialog(existing: step, index: index);
        break;
    }
  }

  // ==================== دوال مساعدة للواجهة ====================
  String _stepTitle(AutomationStep step) {
    switch (step.type) {
      case StepType.text:
        return 'كتابة نص';
      case StepType.key:
        return 'ضغط مفتاح';
      case StepType.mouse:
        return 'نقرة ماوس';
      case StepType.delay:
        return 'انتظار';
      case StepType.loop:
        return 'حلقة (مهملة)';
      case StepType.setCounter:
        return 'تعيين عداد';
      case StepType.incrementCounter:
        return 'زيادة عداد';
      case StepType.waitForWindow:
        return 'انتظار نافذة';
      case StepType.semanticCommand:
        return 'أمر دلالي';
    }
  }

  String _stepDescription(AutomationStep step) {
    switch (step.type) {
      case StepType.text:
        final preview = step.text.length > 45 ? '${step.text.substring(0, 45)}...' : step.text;
        final target = step.targetWindow.trim();
        return '"$preview"${step.repeat > 1 ? '  × ${step.repeat}' : ''}${target.isNotEmpty ? '  ← [$target]' : ''}';
      case StepType.key:
        String display = step.key;
        if (step.modifiers.isNotEmpty) display = '${step.modifiers.join('+')}+$display';
        final target = step.targetWindow.trim();
        return '$display${step.repeat > 1 ? '  × ${step.repeat}' : ''}${target.isNotEmpty ? '  ← [$target]' : ''}';
      case StepType.mouse:
        final target = step.targetWindow.trim();
        return '(${step.x}, ${step.y}) ${step.button == 'left' ? 'أيسر' : step.button == 'right' ? 'أيمن' : 'أوسط'}${step.doubleClick ? ' (مزدوجة)' : ''}${step.repeat > 1 ? '  × ${step.repeat}' : ''}${target.isNotEmpty ? '  ← [$target]' : ''}';
      case StepType.delay:
        return '${step.delayMs} مللي ثانية';
      case StepType.loop:
        return 'تكرار السيناريو (مهمل)';
      case StepType.setCounter:
        return '${step.counterName} ← ${step.counterValue}';
      case StepType.incrementCounter:
        return '${step.counterName} += ${step.incrementAmount}';
      case StepType.waitForWindow:
        return 'انتظار: "${step.targetWindow}" (مهلة ${step.waitTimeoutMs} مللي ثانية)';
      case StepType.semanticCommand:
        final selector = step.commandArguments['automationId'] ?? step.commandArguments['name'] ?? step.commandArguments['className'] ?? 'عنصر';
        return '${step.command} ← $selector${step.targetWindow.trim().isNotEmpty ? '  ← [${step.targetWindow}]' : ''}';
    }
  }

  IconData _stepIcon(AutomationStep step) {
    switch (step.type) {
      case StepType.text:
        return Icons.keyboard_alt_outlined;
      case StepType.key:
        return Icons.key;
      case StepType.mouse:
        return Icons.mouse;
      case StepType.delay:
        return Icons.timer_outlined;
      case StepType.loop:
        return Icons.loop;
      case StepType.setCounter:
        return Icons.numbers;
      case StepType.incrementCounter:
        return Icons.add_circle_outline;
      case StepType.waitForWindow:
        return Icons.window_outlined;
      case StepType.semanticCommand:
        return Icons.account_tree_outlined;
    }
  }

  Color _stepColor(AutomationStep step) {
    switch (step.type) {
      case StepType.text:
        return Colors.blue;
      case StepType.key:
        return Colors.deepPurple;
      case StepType.mouse:
        return Colors.red;
      case StepType.delay:
        return Colors.orange;
      case StepType.loop:
        return Colors.teal;
      case StepType.setCounter:
        return Colors.indigo;
      case StepType.incrementCounter:
        return Colors.green;
      case StepType.waitForWindow:
        return Colors.cyan;
      case StepType.semanticCommand:
        return Colors.purple;
    }
  }

  Widget _statusBadge() {
    final color = _running ? Colors.green : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(30)),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_running ? 'يعمل الآن' : 'جاهز', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    if (!_running) return const SizedBox.shrink();

    final progress = _steps.isEmpty
        ? 0.0
        : (_currentStep ?? 0) / _steps.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0).toDouble(),
            backgroundColor: Colors.grey.shade200,
            color: Colors.indigo,
            minHeight: 4,
          ),
          const SizedBox(height: 2),
          Text(
            'تقدم التنفيذ: ${((progress * 100).toInt()).clamp(0, 100)}%',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  // ==================== دوال اختيار النافذة ====================
  Future<void> _showWindowPicker() async {
    if (_running) return;
    await _refreshOpenWindowsList();
    if (!mounted) return;

    final searchController = TextEditingController();
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final query = searchController.text.trim().toLowerCase();
            final filteredWindows = _openWindows.where((window) {
              final title = (window['title'] ?? '').toLowerCase();
              final process = (window['process'] ?? '').toLowerCase();
              return query.isEmpty || title.contains(query) || process.contains(query);
            }).toList();

            return AlertDialog(
              title: const Text('اختيار نافذة للخطوة'),
              content: SizedBox(
                width: 520,
                height: 430,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'ابحث باسم النافذة أو البرنامج',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          tooltip: 'مسح البحث',
                          onPressed: () {
                            searchController.clear();
                            setDialogState(() {});
                          },
                          icon: const Icon(Icons.clear),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filteredWindows.isEmpty
                          ? Center(
                              child: Text(
                                _openWindows.isEmpty
                                    ? 'لا توجد نوافذ مقروءة. اضغط تحديث أو شغّل التطبيق كمسؤول.'
                                    : 'لا توجد نافذة مطابقة للبحث.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              itemCount: filteredWindows.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final window = filteredWindows[index];
                                final title = window['title'] ?? 'بدون عنوان';
                                final process = window['process'] ?? '';
                                final isSelected = title == _selectedWindowForDropdown;
                                return ListTile(
                                  selected: isSelected,
                                  leading: Icon(
                                    isSelected ? Icons.radio_button_checked : Icons.window_outlined,
                                    color: isSelected ? Colors.indigo : Colors.grey,
                                  ),
                                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: process.isEmpty ? null : Text(process),
                                  trailing: isSelected ? const Icon(Icons.check, color: Colors.indigo) : null,
                                  onTap: () => Navigator.pop(dialogContext, title),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await _refreshOpenWindowsList();
                    setDialogState(() {});
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('تحديث'),
                ),
              ],
            );
          },
        );
      },
    );
    searchController.dispose();

    if (!mounted || selected == null || selected.isEmpty) return;
    setState(() => _selectedWindowForDropdown = selected);
  }

  // ==================== واجهة المستخدم الرئيسية ====================
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xfff6f7fb),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // رأس التطبيق داخل body حتى يملأ Flutter كامل مساحة نافذة Windows.
              Container(
                color: Colors.white,
                padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 12),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.keyboard_alt_outlined, color: primary),
                            ),
                            const SizedBox(width: 12),
                            const Text('أتمتة لوحة المفاتيح',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 10),
                            Text(_currentScenarioName,
                                style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    _statusBadge(),
                  ],
                ),
              ),
              Container(
                color: Colors.grey.shade100,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    _buildMenu(
                      label: 'ملف',
                      items: {
                        'جديد': (icon: Icons.add, onTap: _newScenario),
                        'فتح...': (icon: Icons.folder_open, onTap: _loadScenario),
                        'حفظ': (icon: Icons.save, onTap: _saveCurrentScenario),
                        'حفظ باسم...': (icon: Icons.save_as, onTap: _saveScenarioAsNew),
                        '---': (icon: Icons.remove, onTap: () {}),
                        'تصدير': (icon: Icons.upload_file, onTap: _exportScenario),
                        'استيراد': (icon: Icons.file_download, onTap: _importScenario),
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildMenu(
                      label: 'تعديل',
                      items: {
                        'تعديل الاسم': (icon: Icons.edit, onTap: _renameScenario),
                        'حذف السيناريو': (icon: Icons.delete_forever, onTap: _deleteCurrentScenario),
                        '---': (icon: Icons.remove, onTap: () {}),
                        'تأخير عشوائي': (icon: Icons.timer, onTap: _showRandomDelaySettings),
                        'إعدادات الأداء': (icon: Icons.tune, onTap: _showPerformanceSettings),
                        'إدارة العدادات': (icon: Icons.numbers, onTap: _showCounterManager),
                      },
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder, size: 16, color: Colors.indigo),
                          const SizedBox(width: 4),
                          Text(_currentScenarioName,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildProgressIndicator(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildStepsPanel(),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenu({
    required String label,
    required Map<String, ({IconData icon, VoidCallback onTap})> items,
  }) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
      onSelected: (String value) {
        if (items.containsKey(value) && value != '---') {
          items[value]!.onTap();
        }
      },
      itemBuilder: (context) {
        return items.entries.map((entry) {
          if (entry.key == '---') {
            return const PopupMenuItem<String>(
              value: '---',
              child: Divider(),
            );
          }
          return PopupMenuItem<String>(
            value: entry.key,
            child: Row(
              children: [
                Icon(entry.value.icon, size: 18),
                const SizedBox(width: 12),
                Text(entry.key),
              ],
            ),
          );
        }).toList();
      },
    );
  }

  bool _stepMatchesSearch(AutomationStep step, String query) {
    if (query.isEmpty) return true;
    final values = <String>[
      _stepTitle(step),
      step.text,
      step.key,
      step.button,
      step.counterName,
      step.targetWindow,
      step.previousWindow ?? '',
      step.windowChanged ? 'انتقال نافذة' : '',
      step.type.name,
    ];
    return values.any((value) => value.toLowerCase().contains(query));
  }

  void _clearAllSteps() {
    if (_running || _steps.isEmpty) return;
    _captureEditorChange();
    setState(() {
      _steps.clear();
      _selectedRepeatSteps.clear();
      _loopRangeStart = null;
      _loopRangeEnd = null;
    });
  }

  Widget _buildStepsPanel() {
    final hasSelected = _selectedRepeatSteps.isNotEmpty;
    final hasRange = _loopRangeStart != null && _loopRangeEnd != null;
    final query = _stepSearchQuery.trim().toLowerCase();
    final visibleIndices = List<int>.generate(_steps.length, (index) => index)
        .where((index) => _stepMatchesSearch(_steps[index], query))
        .toList(growable: false);

    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactLayout = constraints.hasBoundedHeight && constraints.maxHeight < 420;

            Widget buildStepList() {
              return _steps.isEmpty
                  ? _emptyState()
                  : visibleIndices.isEmpty
                      ? Center(
                          child: Text(
                            'لا توجد خطوات تطابق البحث',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : query.isNotEmpty
                          ? ListView.builder(
                              controller: _stepsScrollController,
                              itemCount: visibleIndices.length,
                              itemBuilder: (context, visibleIndex) {
                                final index = visibleIndices[visibleIndex];
                                final step = _steps[index];
                                return _buildStepTile(
                                  key: ValueKey(step.id),
                                  step: step,
                                  index: index,
                                );
                              },
                            )
                          : ReorderableListView.builder(
                              scrollController: _stepsScrollController,
                              buildDefaultDragHandles: false,
                              itemCount: _steps.length,
                              onReorderItem: _moveStep,
                              itemBuilder: (context, index) {
                                final step = _steps[index];
                                return _buildStepTile(
                                  key: ValueKey(step.id),
                                  step: step,
                                  index: index,
                                );
                              },
                            );
            }

            final topControls = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                _addButton(icon: Icons.keyboard_alt_outlined, label: 'نص', onPressed: _running ? null : _addText, color: Colors.blue),
                _addButton(icon: Icons.key, label: 'مفتاح', onPressed: _running ? null : _addKey, color: Colors.deepPurple),
                _addButton(icon: Icons.mouse, label: 'ماوس', onPressed: _running ? null : _addMouse, color: Colors.red),
                _addButton(icon: Icons.timer_outlined, label: 'انتظار', onPressed: _running ? null : _addDelay, color: Colors.orange),
                _addButton(icon: Icons.numbers, label: 'تعيين عداد', onPressed: _running ? null : _addSetCounter, color: Colors.indigo),
                _addButton(icon: Icons.add_circle_outline, label: 'زيادة عداد', onPressed: _running ? null : _addIncrementCounter, color: Colors.green),
                _addButton(icon: Icons.lightbulb, label: 'اختصارات', onPressed: _running ? null : _addShortcut, color: Colors.amber),
                _addButton(icon: Icons.account_tree_outlined, label: 'أمر دلالي', onPressed: _running ? null : _addSemanticCommand, color: Colors.purple),
                _addButton(
                  icon: Icons.playlist_add,
                  label: 'إدراج سيناريو',
                  onPressed: _running ? null : _addSavedScenario,
                  color: Colors.purple,
                ),
                _addButton(
                  icon: Icons.window_outlined,
                  label: 'انتظار نافذة',
                  onPressed: _running || _macroRecording || _macroBusy ? null : _addWaitForWindow,
                  color: Colors.cyan,
                ),
                _addButton(
                  icon: _macroRecording ? Icons.stop_circle_outlined : Icons.fiber_manual_record,
                  label: _macroRecording ? 'إيقاف التسجيل' : 'تسجيل ماكرو',
                  onPressed: _running || _macroBusy
                      ? null
                      : (_macroRecording ? _stopMacroRecording : _startMacroRecording),
                  color: _macroRecording ? Colors.red : Colors.teal,
                ),
                if (_macroRecording)
                  _addButton(
                    icon: Icons.delete_outline,
                    label: 'إلغاء التسجيل',
                    onPressed: _macroBusy ? null : _cancelMacroRecording,
                    color: Colors.grey.shade700,
                  ),
                ],
              ),
            ),
            if (_macroRecording || _macroEventCount > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _macroRecording ? Colors.red.shade50 : Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _macroRecording ? Colors.red.shade200 : Colors.teal.shade200,
                  ),
                ),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(
                      _macroRecording ? Icons.fiber_manual_record : Icons.check_circle_outline,
                      size: 17,
                      color: _macroRecording ? Colors.red : Colors.teal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _macroRecording
                            ? 'تسجيل الماكرو نشط: نفّذ الأحداث في البرنامج المستهدف ثم اضغط إيقاف التسجيل.'
                            : 'آخر تسجيل: تمت إضافة $_macroEventCount خطوة إلى السيناريو.',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: TextDirection.rtl,
                  children: [
                    const Text('خطوات الأتمتة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xfff0f1f5), borderRadius: BorderRadius.circular(20)),
                      child: Text('${_steps.length}'),
                    ),
                  ],
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 19),
                      hintText: 'بحث في الخطوات',
                      suffixIcon: _stepSearchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              onPressed: () => setState(() => _stepSearchQuery = ''),
                              icon: const Icon(Icons.clear, size: 18),
                            ),
                    ),
                    onChanged: (value) => setState(() => _stepSearchQuery = value),
                  ),
                ),
                if (_steps.isNotEmpty)
                  Wrap(
                    alignment: WrapAlignment.start,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: _running ? null : _showScenarioRepeatDialog,
                        icon: const Icon(Icons.repeat, size: 16),
                        label: Text(_scenarioPeriodic ? 'تكرار دوري' : 'تكرار ×$_scenarioRepeatCount'),
                      ),
                      TextButton.icon(
                        onPressed: _running ? null : _showSelectRepeatStepsDialog,
                        icon: const Icon(Icons.checklist, size: 16),
                        label: const Text('تحديد خطوات'),
                      ),
                      if (hasSelected)
                        TextButton.icon(
                          onPressed: _running ? null : _clearSelectedSteps,
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('إلغاء التحديد'),
                        ),
                      if (!hasSelected)
                        TextButton.icon(
                          onPressed: _running ? null : _showSetRangeDialog,
                          icon: const Icon(Icons.loop, size: 16),
                          label: const Text('تكرار نطاق'),
                        ),
                      if (hasRange && !hasSelected) ...[
                        TextButton.icon(
                          onPressed: _clearLoopRange,
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('إلغاء النطاق'),
                        ),
                        TextButton.icon(
                          onPressed: _showLoopRangeCountDialog,
                          icon: const Icon(Icons.numbers, size: 16),
                          label: Text('×$_loopRangeCount'),
                        ),
                      ],
                      IconButton(
                        tooltip: 'تراجع',
                        onPressed: _running || !_editorController.canUndo ? null : _undoEditorChange,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        tooltip: 'إعادة',
                        onPressed: _running || !_editorController.canRedo ? null : _redoEditorChange,
                        icon: const Icon(Icons.redo),
                      ),
                      TextButton.icon(
                        onPressed: _running ? null : _clearAllSteps,
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('مسح الكل'),
                      ),
                    ],
                  ),
              ],
            ),
            if (hasSelected) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.checklist, color: Colors.purple, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '✅ خطوات محددة للتكرار: ${_selectedRepeatSteps.length} خطوات ($_loopRangeCount مرات)',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ] else if (hasRange) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.loop, color: Colors.teal, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '🔄 نطاق التكرار: من الخطوة ${_loopRangeStart! + 1} إلى ${_loopRangeEnd! + 1} ($_loopRangeCount مرات، فاصل $_loopDelayMs مللي ثانية)',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: topControls,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: buildStepList()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _addButton({required IconData icon, required String label, required VoidCallback? onPressed, required Color color}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        side: BorderSide(color: color),
        foregroundColor: color,
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
        final compact = maxHeight > 0 && maxHeight < 220;
        final iconBoxSize = compact ? 64.0 : 90.0;
        final iconSize = compact ? 30.0 : 42.0;
        final titleSize = compact ? 16.0 : 20.0;

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: maxHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: compact ? 8 : 20, horizontal: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: iconBoxSize,
                      height: iconBoxSize,
                      decoration: BoxDecoration(
                        color: const Color(0xfff1f2f7),
                        borderRadius: BorderRadius.circular(compact ? 18 : 24),
                      ),
                      child: Icon(Icons.playlist_add, size: iconSize, color: Colors.grey),
                    ),
                    SizedBox(height: compact ? 10 : 18),
                    Text(
                      'لا توجد خطوات',
                      style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'استخدم الأزرار أعلاه لإضافة خطوات',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== دالة _buildStepTile المصححة ====================
  Widget _buildStepTile({required Key key, required AutomationStep step, required int index}) {
    final active = _currentStep == index;
    final isSelectedForRepeat = _selectedRepeatSteps.contains(index);
    final isLoopRangeStart = _loopRangeStart == index;
    final isLoopRangeEnd = _loopRangeEnd == index;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: active
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .06)
            : isSelectedForRepeat
                ? Colors.purple.shade50
                : isLoopRangeStart || isLoopRangeEnd
                    ? Colors.teal.withValues(alpha: .08)
                    : Colors.white,
        border: Border.all(
          color: active
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .45)
              : isSelectedForRepeat
                  ? Colors.purple.withValues(alpha: .4)
                  : isLoopRangeStart || isLoopRangeEnd
                      ? Colors.teal.withValues(alpha: .4)
                      : const Color(0xffe7e8ee),
          width: (active || isSelectedForRepeat || isLoopRangeStart || isLoopRangeEnd) ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.drag_indicator, color: Colors.grey),
              ),
            ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _stepColor(step).withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(_stepIcon(step), color: _stepColor(step)),
            ),
            if (isSelectedForRepeat)
              Container(
                margin: const EdgeInsetsDirectional.only(start: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(4)),
                child: const Text('مختارة', style: TextStyle(color: Colors.white, fontSize: 8)),
              ),
            if (isLoopRangeStart)
              Container(
                margin: const EdgeInsetsDirectional.only(start: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(4)),
                child: const Text('بداية', style: TextStyle(color: Colors.white, fontSize: 8)),
              ),
            if (isLoopRangeEnd)
              Container(
                margin: const EdgeInsetsDirectional.only(start: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(4)),
                child: const Text('نهاية', style: TextStyle(color: Colors.white, fontSize: 8)),
              ),
          ],
        ),
        title: Row(
          children: [
            Text('${index + 1}.', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text(_stepTitle(step), style: const TextStyle(fontWeight: FontWeight.bold)),
            if (active) ...[
              const SizedBox(width: 10),
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_stepDescription(step), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (step.windowChanged) ...[
                const SizedBox(height: 5),
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(Icons.open_in_new, size: 15, color: Colors.indigo.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        step.previousWindow?.trim().isNotEmpty == true
                            ? 'انتقال من: ${step.previousWindow} إلى: ${step.targetWindow}'
                            : 'انتقال إلى: ${step.targetWindow}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.indigo.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'تشغيل من هنا',
              onPressed: _running ? null : () {
                setState(() {
                  _selectedRepeatSteps.clear();
                  _loopRangeStart = index;
                  _loopRangeEnd = _steps.length - 1;
                });
                _runAutomation();
              },
              icon: Icon(Icons.play_arrow_outlined, color: Colors.green.shade700),
              iconSize: 20,
            ),
            IconButton(
              tooltip: 'تعديل',
              onPressed: _running ? null : () => _editStep(index),
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            IconButton(
              tooltip: 'تكرار الخطوة',
              onPressed: _running ? null : () => _duplicateStep(index),
              icon: const Icon(Icons.copy_outlined, size: 20),
            ),
            IconButton(
              tooltip: 'حذف',
              onPressed: _running ? null : () => _deleteStep(index),
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final counterCount = _counterStarts.length;
    String countersPreview = '';
    if (counterCount > 0) {
      final entries = _counterStarts.entries.take(2);
      countersPreview = entries.map((e) {
        final name = e.key.replaceFirst('counter_', '');
        final val = _counterValues[e.key] ?? e.value;
        return '$name=$val';
      }).join('  •  ');
      if (counterCount > 2) countersPreview += '  ...';
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 980;

            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: TextDirection.rtl,
              children: [
                FilledButton.icon(
                  onPressed: _steps.isEmpty || _running ? null : _runAutomation,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('تشغيل'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _running ? _stopAutomation : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('إيقاف'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                ),
              ],
            );

            final windowPicker = SizedBox(
              width: compact ? double.infinity : 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        alignment: Alignment.centerRight,
                        hint: const Text(
                          'اختر النافذة المستهدفة...',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        value: _uniqueOpenWindows().any(
                                (window) => window['title'] == _selectedWindowForDropdown)
                            ? _selectedWindowForDropdown
                            : null,
                        icon: const Icon(Icons.window, size: 18, color: Colors.indigo),
                        items: _uniqueOpenWindows().map<DropdownMenuItem<String>>((window) {
                          final title = window['title'] ?? 'بدون عنوان';
                          return DropdownMenuItem<String>(
                            value: title,
                            child: Row(
                              textDirection: TextDirection.rtl,
                              children: [
                                const Icon(Icons.window, size: 14, color: Colors.grey),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${title.isEmpty ? 'بدون عنوان' : title}  [${window['process'] ?? ''}]',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: _openWindows.isNotEmpty
                            ? (String? newValue) {
                                setState(() => _selectedWindowForDropdown = newValue);
                              }
                            : null,
                      ),
                    ),
                  ),
                  if (_openWindows.isNotEmpty && _selectedWindowForDropdown != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'النافذة المستهدفة: $_selectedWindowForDropdown',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 10, color: Colors.indigo),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_openWindows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Text(
                        'لا توجد نوافذ مقروءة؛ اضغط تحديث أو شغّل التطبيق كمسؤول.',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 10, color: Colors.orange),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            );

            final windowTools = Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: TextDirection.rtl,
              children: [
                IconButton(
                  tooltip: 'تحديث النوافذ المفتوحة',
                  onPressed: _running ? null : _refreshOpenWindowsList,
                  icon: const Icon(Icons.refresh, color: Colors.indigo),
                ),
                IconButton(
                  tooltip: 'اختيار نافذة مع البحث',
                  onPressed: _running ? null : _showWindowPicker,
                  icon: const Icon(Icons.manage_search, color: Colors.indigo),
                ),
              ],
            );

            final statusPanel = Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: TextDirection.rtl,
                children: [
                  _statusBadge(),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _running
                            ? 'جاري تنفيذ الخطوة ${(_currentStep ?? 0) + 1} من ${_steps.length}'
                            : 'جاهز للتشغيل',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: _running
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (_running && _currentScenarioIteration > 0)
                        Text(
                          _scenarioPeriodic
                              ? 'الدورة $_currentScenarioIteration (دوري)'
                              : 'الدورة $_currentScenarioIteration من $_totalScenarioIterations',
                          style: const TextStyle(fontSize: 11, color: Colors.indigo),
                        ),
                      if (_running && _currentLoopIteration > 0)
                        Text(
                          'تكرار الخطوات $_currentLoopIteration من $_totalLoopIterations',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      if (!_running && _scenarioPeriodic)
                        Text(
                          'الوضع الدوري: كل $_scenarioIntervalMs مللي ثانية',
                          style: const TextStyle(fontSize: 10, color: Colors.indigo),
                        )
                      else if (!_running && _scenarioRepeatCount > 1)
                        Text(
                          'تكرار السيناريو: ×$_scenarioRepeatCount، الفاصل $_scenarioIntervalMs مللي ثانية',
                          style: const TextStyle(fontSize: 10, color: Colors.indigo),
                        ),
                      if (_randomDelayEnabled && !_running)
                        Text(
                          'تأخير عشوائي ($_randomDelayMin–$_randomDelayMax مللي ثانية)',
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      if (_selectedRepeatSteps.isNotEmpty && !_running)
                        Text(
                          'خطوات محددة: ${_selectedRepeatSteps.length} (×$_loopRangeCount)',
                          style: const TextStyle(fontSize: 10, color: Colors.purple),
                        ),
                      if (_loopRangeStart != null &&
                          _loopRangeEnd != null &&
                          !_running &&
                          _selectedRepeatSteps.isEmpty)
                        Text(
                          'النطاق: ${_loopRangeStart! + 1} ← ${_loopRangeEnd! + 1} (×$_loopRangeCount)',
                          style: const TextStyle(fontSize: 10, color: Colors.teal),
                        ),
                      if (counterCount > 0 && !_running)
                        Text(
                          countersPreview,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 10, color: Colors.indigo),
                          overflow: TextOverflow.ellipsis,
                        ),
                      TextButton(
                        onPressed: _showCounterManager,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(50, 20),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          textDirection: TextDirection.rtl,
                          children: [
                            const Icon(Icons.numbers, size: 14, color: Colors.indigo),
                            const SizedBox(width: 4),
                            Text(
                              counterCount > 0 ? 'العدادات ($counterCount)' : 'إضافة عداد',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.indigo,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  actions,
                  const SizedBox(height: 10),
                  windowPicker,
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    textDirection: TextDirection.rtl,
                    children: [windowTools, Flexible(child: statusPanel)],
                  ),
                ],
              );
            }

            return Row(
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                actions,
                const SizedBox(width: 18),
                windowTools,
                const SizedBox(width: 8),
                windowPicker,
                const SizedBox(width: 18),
                Expanded(child: Align(alignment: Alignment.centerLeft, child: statusPanel)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class KeyboardKey {
  const KeyboardKey(this.name, this.code);
  final String name;
  final String code;
}

const allKeys = <KeyboardKey>[
  KeyboardKey('A', 'A'),
  KeyboardKey('B', 'B'),
  KeyboardKey('C', 'C'),
  KeyboardKey('D', 'D'),
  KeyboardKey('E', 'E'),
  KeyboardKey('F', 'F'),
  KeyboardKey('G', 'G'),
  KeyboardKey('H', 'H'),
  KeyboardKey('I', 'I'),
  KeyboardKey('J', 'J'),
  KeyboardKey('K', 'K'),
  KeyboardKey('L', 'L'),
  KeyboardKey('M', 'M'),
  KeyboardKey('N', 'N'),
  KeyboardKey('O', 'O'),
  KeyboardKey('P', 'P'),
  KeyboardKey('Q', 'Q'),
  KeyboardKey('R', 'R'),
  KeyboardKey('S', 'S'),
  KeyboardKey('T', 'T'),
  KeyboardKey('U', 'U'),
  KeyboardKey('V', 'V'),
  KeyboardKey('W', 'W'),
  KeyboardKey('X', 'X'),
  KeyboardKey('Y', 'Y'),
  KeyboardKey('Z', 'Z'),
  KeyboardKey('0', '0'),
  KeyboardKey('1', '1'),
  KeyboardKey('2', '2'),
  KeyboardKey('3', '3'),
  KeyboardKey('4', '4'),
  KeyboardKey('5', '5'),
  KeyboardKey('6', '6'),
  KeyboardKey('7', '7'),
  KeyboardKey('8', '8'),
  KeyboardKey('9', '9'),
  KeyboardKey('`', '`'),
  KeyboardKey('-', '-'),
  KeyboardKey('=', '='),
  KeyboardKey('[', '['),
  KeyboardKey(']', ']'),
  KeyboardKey('\\', '\\'),
  KeyboardKey(';', ';'),
  KeyboardKey("'", "'"),
  KeyboardKey(',', ','),
  KeyboardKey('.', '.'),
  KeyboardKey('/', '/'),
  KeyboardKey('Enter', 'ENTER'),
  KeyboardKey('Tab', 'TAB'),
  KeyboardKey('Escape', 'ESC'),
  KeyboardKey('Space', 'SPACE'),
  KeyboardKey('Backspace', 'BACKSPACE'),
  KeyboardKey('Delete', 'DELETE'),
  KeyboardKey('Insert', 'INSERT'),
  KeyboardKey('السهم الأيسر', 'LEFT'),
  KeyboardKey('السهم الأيمن', 'RIGHT'),
  KeyboardKey('السهم الأعلى', 'UP'),
  KeyboardKey('السهم الأسفل', 'DOWN'),
  KeyboardKey('Home', 'HOME'),
  KeyboardKey('النهاية', 'END'),
  KeyboardKey('صفحة لأعلى', 'PAGEUP'),
  KeyboardKey('صفحة لأسفل', 'PAGEDOWN'),
  KeyboardKey('F1', 'F1'),
  KeyboardKey('F2', 'F2'),
  KeyboardKey('F3', 'F3'),
  KeyboardKey('F4', 'F4'),
  KeyboardKey('F5', 'F5'),
  KeyboardKey('F6', 'F6'),
  KeyboardKey('F7', 'F7'),
  KeyboardKey('F8', 'F8'),
  KeyboardKey('F9', 'F9'),
  KeyboardKey('F10', 'F10'),
  KeyboardKey('F11', 'F11'),
  KeyboardKey('F12', 'F12'),
  KeyboardKey('F13', 'F13'),
  KeyboardKey('F14', 'F14'),
  KeyboardKey('F15', 'F15'),
  KeyboardKey('F16', 'F16'),
  KeyboardKey('F17', 'F17'),
  KeyboardKey('F18', 'F18'),
  KeyboardKey('F19', 'F19'),
  KeyboardKey('F20', 'F20'),
  KeyboardKey('F21', 'F21'),
  KeyboardKey('F22', 'F22'),
  KeyboardKey('F23', 'F23'),
  KeyboardKey('F24', 'F24'),
  KeyboardKey('طباعة الشاشة', 'PRINTSCREEN'),
  KeyboardKey('إيقاف مؤقت', 'PAUSE'),
  KeyboardKey('تثبيت الأحرف', 'CAPSLOCK'),
  KeyboardKey('تثبيت الأرقام', 'NUMLOCK'),
  KeyboardKey('قفل التمرير', 'SCROLLLOCK'),
];