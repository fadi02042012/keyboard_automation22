import 'dart:convert';
import 'dart:typed_data';

import '../models/automation_step.dart';
import '../models/scenario.dart';

/// Result of decoding a scenario file from JSON.
class ImportedScenario {
  const ImportedScenario({
    required this.name,
    required this.steps,
    this.id,
    this.schemaVersion = 1,
    this.wasLegacyList = false,
    this.appVersion,
  });

  final String? id;
  final String name;
  final List<AutomationStep> steps;
  final int schemaVersion;
  final bool wasLegacyList;
  final String? appVersion;
}

/// File-format boundary for scenario import/export.
///
/// The service deliberately does not access the file picker. This keeps JSON
/// parsing deterministic and unit-testable while the UI remains responsible
/// for selecting a path and presenting messages to the user.
class ScenarioFileService {
  const ScenarioFileService({
    this.maxSteps = 10000,
  });

  static const int currentSchemaVersion = 1;
  static const String documentType = 'keyboard_automation_scenario';

  final int maxSteps;

  Uint8List encodeScenario({
    required Scenario scenario,
    required String appVersion,
  }) {
    final document = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'type': documentType,
      'id': scenario.id,
      'name': scenario.name,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': appVersion,
      'steps': scenario.steps.map((step) => step.toJson()).toList(),
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(document)),
    );
  }

  ImportedScenario decodeScenario(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('ملف السيناريو فارغ');
    }

    final decoded = jsonDecode(content);
    String? id;
    var name = 'سيناريو مستورد';
    var schemaVersion = currentSchemaVersion;
    var wasLegacyList = false;
    String? appVersion;
    late final List<dynamic> rawSteps;

    if (decoded is List) {
      // Backward compatibility with the original export format.
      rawSteps = decoded;
      wasLegacyList = true;
    } else if (decoded is Map) {
      final root = Map<String, dynamic>.from(decoded);
      final rawVersion = root['schemaVersion'];
      schemaVersion = rawVersion is num
          ? rawVersion.toInt()
          : int.tryParse(rawVersion?.toString() ?? '') ?? currentSchemaVersion;
      if (schemaVersion < 1 || schemaVersion > currentSchemaVersion) {
        throw FormatException('إصدار ملف غير مدعوم: $schemaVersion');
      }

      final rawType = root['type']?.toString();
      if (rawType != null && rawType != documentType) {
        throw const FormatException('نوع ملف السيناريو غير صحيح');
      }

      id = root['id']?.toString();
      final rawAppVersion = root['appVersion']?.toString().trim();
      if (rawAppVersion != null && rawAppVersion.isNotEmpty) {
        appVersion = rawAppVersion;
      }
      final rawName = root['name']?.toString().trim();
      if (rawName != null && rawName.isNotEmpty) {
        name = rawName;
      }

      final value = root['steps'];
      if (value is! List) {
        throw const FormatException('حقل steps غير موجود أو غير صالح');
      }
      rawSteps = value;
    } else {
      throw const FormatException('تنسيق JSON غير مدعوم');
    }

    if (rawSteps.isEmpty) {
      throw const FormatException('لا توجد خطوات في الملف');
    }
    if (rawSteps.length > maxSteps) {
      throw FormatException(
        'عدد الخطوات يتجاوز الحد المسموح ($maxSteps)',
      );
    }

    final steps = <AutomationStep>[];
    for (final item in rawSteps) {
      if (item is! Map) continue;
      try {
        steps.add(
          AutomationStep.fromJson(Map<String, dynamic>.from(item)),
        );
      } on FormatException {
        // Ignore an individual malformed item; valid steps remain usable.
      }
    }

    if (steps.isEmpty) {
      throw const FormatException('لا توجد خطوات صالحة في الملف');
    }

    return ImportedScenario(
      id: id,
      name: name,
      steps: List.unmodifiable(steps),
      schemaVersion: schemaVersion,
      wasLegacyList: wasLegacyList,
      appVersion: appVersion,
    );
  }
}
