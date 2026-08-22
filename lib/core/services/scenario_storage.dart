import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../app_logger.dart';
import '../models/scenario.dart';

/// Persistence boundary for saved scenarios.
///
/// The storage key and JSON representation are intentionally unchanged for
/// backward compatibility with existing installations.
class ScenarioStorage {
  const ScenarioStorage({this.key = 'scenarios'});

  final String key;

  Future<List<Scenario>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(key) ?? '[]';
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const <Scenario>[];

      final scenarios = <Scenario>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          scenarios.add(Scenario.fromJson(Map<String, dynamic>.from(item)));
        } on FormatException {
          // A malformed item should not make valid scenarios unavailable.
        }
      }
      return scenarios;
    } on FormatException catch (error, stackTrace) {
      AppLogger.warning(
        'Saved scenarios contain invalid JSON; starting with an empty list.',
        error: error,
        stackTrace: stackTrace,
        name: 'storage',
      );
      return const <Scenario>[];
    } on Exception catch (error, stackTrace) {
      AppLogger.warning(
        'Saved scenarios could not be loaded; starting with an empty list.',
        error: error,
        stackTrace: stackTrace,
        name: 'storage',
      );
      return const <Scenario>[];
    }
  }

  Future<void> save(List<Scenario> scenarios) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(scenarios.map((scenario) => scenario.toJson()).toList());
    final persisted = await prefs.setString(key, encoded);
    if (!persisted) {
      throw StateError('Shared preferences rejected scenario persistence.');
    }
  }
}
