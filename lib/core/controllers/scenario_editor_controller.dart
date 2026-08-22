import '../models/automation_step.dart';

/// Keeps bounded undo/redo history for scenario editing operations.
///
/// The controller is intentionally independent from Flutter widgets. The page
/// owns the visible list and calls [capture] before a mutation, then applies
/// the returned snapshot from [undo] or [redo] inside setState.
class ScenarioEditorController {
  ScenarioEditorController({this.maxHistory = 50});

  final int maxHistory;
  final List<List<AutomationStep>> _undoStack = [];
  final List<List<AutomationStep>> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void capture(List<AutomationStep> current) {
    _undoStack.add(_clone(current));
    if (_undoStack.length > maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  List<AutomationStep>? undo(List<AutomationStep> current) {
    if (!canUndo) return null;
    _redoStack.add(_clone(current));
    return _undoStack.removeLast();
  }

  List<AutomationStep>? redo(List<AutomationStep> current) {
    if (!canRedo) return null;
    _undoStack.add(_clone(current));
    return _redoStack.removeLast();
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }

  List<AutomationStep> _clone(List<AutomationStep> source) {
    return source.map((step) => step.copy()).toList();
  }
}
