import 'automation_step.dart';

class Scenario {
  final String id;
  String name;
  final List<AutomationStep> steps;

  Scenario({required this.id, required this.name, required this.steps});

  Scenario copy() {
    return Scenario(
      id: id,
      name: name,
      steps: steps.map((e) => e.copy()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'steps': steps.map((e) => e.toJson()).toList(),
      };

  factory Scenario.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    if (rawSteps is! List) {
      throw const FormatException('Invalid scenario steps');
    }
    final steps = <AutomationStep>[];
    for (final item in rawSteps) {
      if (item is! Map) continue;
      try {
        steps.add(AutomationStep.fromJson(Map<String, dynamic>.from(item)));
      } on FormatException {
        // Ignore malformed individual steps while preserving the scenario.
      }
    }
    return Scenario(
      id: json['id'] == null || json['id'].toString().trim().isEmpty
          ? '${DateTime.now().microsecondsSinceEpoch}'
          : json['id'].toString(),
      name: AutomationStep.asString(json['name'], 'سيناريو غير مسمى').trim(),
      steps: steps,
    );
  }
}
